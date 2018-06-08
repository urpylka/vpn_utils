#!/bin/bash
# vpn-manager script is conection manager for xl2tpd over IPSec
# Written by Artem Smirnov <urpylka@gmail.com>

if [[ `whoami` != "root" ]]
then
  echo "Script must be run as root."
  exit 1
fi

CONNECTION_NAME="coex-space"
REMOTE_IP="192.168.254.254"
VPN_SERVER="coex.space"

echo "$(date) Создан ip-up скрипт"
cat <<EOF | tee /etc/ppp/ip-up.d/vpn-routes-up > /dev/null && chmod a+x /etc/ppp/ip-up.d/vpn-routes-up
#!/bin/sh
# ppp.ip-up hook script for xl2tpd
# Written by Artem Smirnov <urpylka@gmail.com>

REMOTE_IP="${REMOTE_IP}"
REMOTE_NETWORK_24=\$(echo \$PPP_LOCAL | sed 's/[0-9]*$/0\/24/')

if [ "\$PPP_REMOTE" = "\$REMOTE_IP" ];
then /sbin/ip route add \$REMOTE_NETWORK_24 via \$PPP_REMOTE
fi
EOF

echo "$(date) Создан ip-down скрипт"
cat <<EOF | tee /etc/ppp/ip-down.d/vpn-routes-down > /dev/null && chmod a+x /etc/ppp/ip-down.d/vpn-routes-down
#!/bin/sh
# ppp.ip-down hook script for xl2tpd
# Written by Artem Smirnov <urpylka@gmail.com>

REMOTE_IP="${REMOTE_IP}"
REMOTE_NETWORK_24=\$(echo \$PPP_LOCAL | sed 's/[0-9]*$/0\/24/')

if [ "\$PPP_REMOTE" = "\$REMOTE_IP" ];
then
  /usr/sbin/ipsec down ${CONNECTION_NAME}
  touch /dev/shm/ipsec.lock
fi
EOF

touch /dev/shm/ipsec.lock
START=$(date +%s)
CONNECTED=false
echo "$(date) Запуск vpn manager"
while true
do
  # send ping 3 times with 0.2 second interval
  if ping ${REMOTE_IP} -n -q -i 0.2 -c 3 -W 1 > /dev/null 2>&1
  then
    DURATION=$(($(date +%s)-$START))
    echo -ne "\033[0;32m\033[1mUP:\033[0m\033[0m $DURATION\r"
    sleep 1
  else
    echo
    CONNECTED=false
    echo "$(date) Нет доступа к удаленной сети!"
    echo "$(date) Отключаю xl2tpd сессию…"
    echo "d ${CONNECTION_NAME}" | tee /var/run/xl2tpd/l2tp-control > /dev/null
    for s in $(seq 1 30); do
      if [[ -e /dev/shm/ipsec.lock ]];
      then
        rm -f /dev/shm/ipsec.lock
        break
      fi
      if [ "$s" = "30" ]
      then
        echo "$(date) Перезапускаю xl2tpd…"
        systemctl restart xl2tpd
        echo "$(date) Отключаю IPSec туннель…"
        ipsec down ${CONNECTION_NAME} > /dev/null
        sleep 1
      fi
      sleep 1
    done
    echo "$(date) Проверяю доступ до ${VPN_SERVER}…"
    while ! ping ${VPN_SERVER} -n -q -i 0.2 -c 3 -W 1 > /dev/null 2>&1
    do
      if $CONNECTED
      then DURATION=$(($(date +%s)-$START))
      else
        START=$(date +%s)
        DURATION=0
        CONNECTED=true
      fi
      echo -ne "\033[0;31m\033[1mDOWN:\033[0m\033[0m $DURATION\r"
      sleep 1
    done
    echo
    echo "$(date) Поднимаю IPSec туннель…"
    ipsec up ${CONNECTION_NAME} > /dev/null
    # вот здесь может проверить есть ли туннель
    sleep 10
    echo "$(date) Подключаю xl2tpd…"
    echo "c ${CONNECTION_NAME}" | tee /var/run/xl2tpd/l2tp-control > /dev/null
    for s in $(seq 1 30); do
       if ping ${REMOTE_IP} -n -q -i 0.2 -c 3 -W 1 > /dev/null 2>&1
       then
         echo "$(date) Успешное подключение"
         START=$(date +%s)
         DURATION=0
         CONNECTED=true
         break
       fi
       if [ "$s" = "30" ]
       then touch /dev/shm/ipsec.lock
       fi
    done
  fi
done
