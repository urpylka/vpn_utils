#!/bin/bash
# vpn-server-cli script for manage clients configs of VPN server
# Written by Artem Smirnov <urpylka@gmail.com>

if [[ `whoami` != "root" ]]
then
  echo "Script must be run as root."
  exit 1
fi

# Нужно усовершенствовать алгоритм, тк он может указывать на 0.0.0.0 или 255.255.255.255
check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

SECRETS_FILE="/etc/ppp/chap-secrets"

add_client(){
  while true; do
    echo -n "Username: "
    read USERNAME
    if ! cat ${SECRETS_FILE} | grep "\"${USERNAME}\"" > /dev/null
    then break
    else echo "Login \"${USERNAME}\" is busy"
    fi
  done

  echo -n "Password for user (leave blank for set random): "
  read PASS
  if [[ -z ${PASS} ]]; then
    PASS=$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' < /dev/urandom | head -c 16)
    echo "Password for ${USERNAME} is \"${PASS}\""
  fi

  while true; do
    echo -n "User IP: "
    read IP
    if check_ip ${IP}
    then
      if ! cat ${SECRETS_FILE} | grep "${IP}$" > /dev/null
      then break
      else echo "IP \"${IP}\" is busy"
      fi
    else echo "IP \"${IP}\" is incorrect"
    fi
  done

  echo "\"${USERNAME}\" l2tpd \"${PASS}\" ${IP}" | tee -a ${SECRETS_FILE}
  add_route $(get_subnet_24 ${IP})

  iptables-restore < /etc/iptables.rules
  service xl2tpd restart 2>/dev/null
}

show_clients(){
  echo -n "Enter subnetwork, IP or username (leave blank for show all users): "
  read SEARCH_REQ
  if [[ ! -z ${SEARCH_REQ} ]]; then
    if check_ip ${SEARCH_REQ}
    then
      if echo ${SEARCH_REQ} | grep '.0$' # > /dev/null
      then echo "NETWORK" && cat ${SECRETS_FILE} | grep "$(echo ${SEARCH_REQ} | sed 's/.0$//')"
      else cat ${SECRETS_FILE} | grep "${SEARCH_REQ}$"
      fi
    else cat ${SECRETS_FILE} | grep "\"${SEARCH_REQ}\""
    fi
  else cat ${SECRETS_FILE}
  fi
}

change_client(){
  echo -n "Enter IP or username: "
  read SEARCH_REQ
  if check_ip ${SEARCH_REQ}
  then SEARCH_RESP=$(cat ${SECRETS_FILE} | grep "${SEARCH_REQ}$")
  else SEARCH_RESP=$(cat ${SECRETS_FILE} | grep "\"${SEARCH_REQ}\"")
  fi
  if [[ -z ${SEARCH_RESP} ]];
  then echo "По данному запросу не найден пользователь"
  else
    echo ${SEARCH_RESP}
    while true; do
      echo -n "Enter new username (leave blank for use old): "
      read USERNAME
      if [[ ! -z ${USERNAME} ]]; then
        if ! sudo cat ${SECRETS_FILE} | grep "^\"${USERNAME}\"" > /dev/null
        then break
        else echo "Login \"${USERNAME}\" is busy"
        fi
      else
        USERNAME=$(echo ${SEARCH_RESP} | grep -Eo '^("([A-Za-z0-9_-]+)")' | grep -Eo '[A-Za-z0-9_-]+')
        break
      fi
    done

    echo -n "Password for user (leave blank for set random): "
    read PASS
    # grep -Eo '("([A-Za-z0-9]+)")' | tail -n1 | grep -Eo '[A-Za-z0-9]+'
    if [[ -z ${PASS} ]]; then
      PASS=$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' < /dev/urandom | head -c 16)
      echo "Password for ${USERNAME} is \"${PASS}\""
    fi

    OLD_IP=$(echo ${SEARCH_RESP} | grep -Eo '[0-9\.]+$')
    while true; do
      echo -n "Enter new user IP (leave blank for use old): "
      read IP
      if [[ ! -z ${IP} ]]; then
        if check_ip ${IP}
        then
          if ! cat ${SECRETS_FILE} | grep "${IP}$" > /dev/null
          then break
          else echo "IP \"${IP}\" is busy"
          fi
        else echo "IP \"${IP}\" is incorrect"
        fi
      else
        IP=${OLD_IP}
        break
      fi
    done

    NEW_RECORD="\"${USERNAME}\" l2tpd \"${PASS}\" ${IP}"
    echo ${NEW_RECORD}
    sed -i "s/${SEARCH_RESP}/${NEW_RECORD}/" ${SECRETS_FILE}
    if [ ${OLD_IP} != ${IP} ] && ! used_route $(get_subnet_24 ${OLD_IP})
    then del_route $(get_subnet_24 ${OLD_IP})
    fi
    add_route $(get_subnet_24 ${IP})

    iptables-restore < /etc/iptables.rules
    service xl2tpd restart 2>/dev/null
  fi
}

delete_client(){
  echo -n "Enter IP or username: "
  read SEARCH_REQ
  if check_ip ${SEARCH_REQ}
  then SEARCH_RESP=$(cat ${SECRETS_FILE} | grep "${SEARCH_REQ}$")
  else SEARCH_RESP=$(cat ${SECRETS_FILE} | grep "\"${SEARCH_REQ}\"")
  fi
  if [[ -z ${SEARCH_RESP} ]];
  then echo "По данному запросу не найден пользователь"
  else
    echo ${SEARCH_RESP}
    echo "Press Enter for delete..."
    read OK
    OLD_IP=$(echo ${SEARCH_RESP} | grep -Eo '[0-9\.]+$')
    sed -i "/${SEARCH_RESP}/d" ${SECRETS_FILE}
    if ! used_route $(get_subnet_24 ${OLD_IP})
    then del_route $(get_subnet_24 ${OLD_IP})
    fi

    iptables-restore < /etc/iptables.rules
    service xl2tpd restart 2>/dev/null
  fi
}

IPT_FILE="/etc/iptables.rules"

get_subnet_24(){
  if [[ -z $1 ]];
  then
    echo "Вы не указали IP"
    exit 1
  else
    if check_ip $1
    then CLIENT_IP=$1
    else
      echo "Указан неккорректный IP: $1"
      exit 2
    fi
  fi

  REMOTE_NETWORK_24=$(echo ${CLIENT_IP} | sed 's/[0-9]*$/0\/24/')
  echo ${REMOTE_NETWORK_24}
}

exists_route(){
  REMOTE_NETWORK_24=$1
  SEARCH_RESP="-A FORWARD -s ${REMOTE_NETWORK_24} -d ${REMOTE_NETWORK_24} -i ppp+ -o ppp+ -j ACCEPT"

  if cat ${IPT_FILE} | grep -e "${SEARCH_RESP}" > /dev/null
  then return 0
  else return 1
  fi
}

used_route(){
  REMOTE_NETWORK_24=$1
  if cat ${SECRETS_FILE} | grep -e "$(echo ${REMOTE_NETWORK_24} | grep -Eo '^([0-9]+\.){3}')" > /dev/null
  then echo "Подсеть ${REMOTE_NETWORK_24} используется"; return 0
  else echo "Подсеть ${REMOTE_NETWORK_24} не используется"; return 1
  fi
}

# ! used_route ${REMOTE_NETWORK_24
# echo "Нет IP из подсети ${REMOTE_NETWORK_24} в ${SECRETS_FILE}."

del_route(){
  REMOTE_NETWORK_24=$1
  if exists_route ${REMOTE_NETWORK_24};
  then
    echo "Найден маршрут в сеть ${REMOTE_NETWORK_24} в ${IPT_FILE}. Удаляю..."
    SEARCH_RESP="-A FORWARD -s ${REMOTE_NETWORK_24} -d ${REMOTE_NETWORK_24} -i ppp+ -o ppp+ -j ACCEPT"
    SEARCH_RESP_ESCAPE=$(echo ${SEARCH_RESP} | sed -e 's/\//\\\//g')
    sed -i "/${SEARCH_RESP_ESCAPE}/d" ${IPT_FILE}
  fi
}

# used_route ${REMOTE_NETWORK_24}
# echo "Найден IP из подсети ${REMOTE_NETWORK_24} в ${SECRETS_FILE}."

add_route(){
  END_POSITION_STRING="-A FORWARD -j DROP"
  REMOTE_NETWORK_24=$1
  if ! exists_route ${REMOTE_NETWORK_24};
  then
    echo "Не найден маршрут в ${REMOTE_NETWORK_24} сеть в ${IPT_FILE}. Добавляю..."
    NEW_RECORD="-A FORWARD -s ${REMOTE_NETWORK_24} -d ${REMOTE_NETWORK_24} -i ppp+ -o ppp+ -j ACCEPT"
    # Знаки % тк последовательность содержет /
    sed -i "s%${END_POSITION_STRING}%${NEW_RECORD}\n${END_POSITION_STRING}%" ${IPT_FILE}
  fi
}

case "$1" in
  add) add_client;;
  del) delete_client;;
  show) show_clients;;
  ch) change_client;;
  *) echo "Enter one of: add, del, show, ch";;
esac
