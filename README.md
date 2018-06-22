# Доступ к дрону через интернет

Так как в большинстве случаев сотовый модем, находящийся на дроне, не имеет белого IP адреса, а также существует необходимость объединять несколько агентов (дроны, зарядные станции, управляющий персонал) в единую сеть, доступ к дрону организован через VPN сервер.

## Настройка

Настройка состоит из двух частей: настройка сервера (серверная часть) и настройка дрона (клиентская часть).

### Настройка серверной части

В качестве сервера было решено использовать libreswan (IPSec) + xl2tpd, т.к. в отличие от openvpn это решение поддерживается из коробки большинством операционных систем.

Для настройки существует готовый проект (скрипт + руковдство для подключения) для настройки VPN сервера https://github.com/hwdsl2/setup-ipsec-vpn

Однако в этом решении используется единый логин для подключения, а IP адреса выдаются из указанного диапазона. Данная концепция мб не совсем удобна, так как:
1. IP адреса не привязаны к логинам, а значит одни и те же агенты могут произвольно менять свои адреса при смене сессии.
2. Нет возможности разграничить доступ для групп пользователей. Чтобы одна группа не имела доступа к другой.

Для решения этих проблем необходимо изменить ряд настроек:
1. Заменить uniqueids=no в /etc/ipsec.conf на uniqueids=yes
2. Удалить все записи /etc/ipsec.secrets со звездочкой вместо конкретного IP
3. Удалить ip range = $L2TP_POOL в /etc/xl2tpd/xl2tpd.conf, local ip = $L2TP_LOCAL заменить на local ip = 192.168.254.254, добавить exclusive = yes и assign ip = no
4. Удалить lcp-echo-failure 4 и lcp-echo-interval 30 из /etc/ppp/options.xl2tpd, заменить proxyarp на noproxyarp, добавить persist

Далее для удобства управления пользователями написал вот этот скрипт https://github.com/urpylka/vpn_utils/blob/master/vpn-server-cli.sh

### Настройка клиентской части

```bash
wget https://raw.githubusercontent.com/urpylka/vpn_utils/master/vpn-client-installer.sh
chmod +x ./vpn-client-installer.sh
wget https://raw.githubusercontent.com/urpylka/vpn_utils/master/vpn-manager.sh
chmod +x ./vpn-manager.sh
sudo ./vpn-client-installer.sh VPN_SERVER_IP VPN_IPSEC_PSK VPN_USER VPN_PASSWORD
```

### Настройка интернета через 4G модем

```bash
sudo apt install network-manager
sudo nmcli connection add connection.type gsm connection.interface-name cdc-wdm0 \
  connection.id "gsm" gsm.username mts gsm.password mts gsm.apn "internet.mts.ru" ipv4.method auto ipv6.method ignore \
  connection.autoconnect yes
```

> После включения network-manager Wi-Fi точка доступа настроенная в образе перестанет работать, единственное как можно подключиться к Raspberry по сети - это через Ethernet на котором настроен DHCP сервер.
