#!/bin/bash
# vpn-manager script for install xl2tpd over ipsec with simple vpn-manager
# Written by Artem Smirnov <urpylka@gmail.com>

# USE: sudo ./vpn-client-installer.sh VPN_SERVER_IP VPN_IPSEC_PSK VPN_USER VPN_PASSWORD

if [[ `whoami` != "root" ]]
then
  echo "Script must be run as root."
  exit 1
fi

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

if [[ ! -z $1 ]];
then
  if check_ip $1
  then VPN_SERVER_IP=$1
  else echo "Необходимо указать IP адрес"
  fi
else
  echo "Необходимо указать VPN_SERVER_IP"
  exit 11
fi

if [[ ! -z $2 ]];
then VPN_IPSEC_PSK=$2
else
  echo "Необходимо указать VPN_IPSEC_PSK"
  exit 12
fi

if [[ ! -z $3 ]];
then VPN_USER=$3
else
  echo "Необходимо указать VPN_USER"
  exit 13
fi


if [[ ! -z $4 ]];
then VPN_PASSWORD=$4
else
  echo "Необходимо указать VPN_PASSWORD"
  exit 14
fi

CONNECTION_NAME="my-vpn-connection"

apt-get update
apt-get -y install strongswan xl2tpd

cat > /etc/ipsec.conf <<EOF
# ipsec.conf - strongSwan IPsec configuration file

# basic configuration

config setup
  # strictcrlpolicy=yes
  uniqueids = yes

# Add connections here.

# Sample VPN connections

conn %default
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  keyexchange=ikev1
  authby=secret
  ike=aes128-sha1-modp1024,3des-sha1-modp1024!
  esp=aes128-sha1-modp1024,3des-sha1-modp1024!

conn ${CONNECTION_NAME}
  keyexchange=ikev1
  left=%defaultroute
  auto=add
  authby=secret
  type=transport
  leftprotoport=17/1701
  rightprotoport=17/1701
  right=$VPN_SERVER_IP
EOF

cat > /etc/ipsec.secrets <<EOF
: PSK "$VPN_IPSEC_PSK"
EOF

chmod 600 /etc/ipsec.secrets

cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[lac ${CONNECTION_NAME}]
lns = $VPN_SERVER_IP
;ppp debug = yes
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
;redial = yes
EOF

cat > /etc/ppp/options.l2tpd.client <<EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-chap
noccp
noauth
mtu 1280
mru 1280
noipdefault
defaultroute
usepeerdns
connect-delay 5000
name $VPN_USER
password $VPN_PASSWORD
EOF

chmod 600 /etc/ppp/options.l2tpd.client

mkdir -p /var/run/xl2tpd
touch /var/run/xl2tpd/l2tp-control

service strongswan restart
service xl2tpd restart

cat <<EOF > $(pwd)/vpn-manager.service
[Unit]
Description=Simple manager of VPN connection
After=network.target

[Service]
ExecStart=$(pwd)/vpn-manager.sh
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

systemctl enable $(pwd)/vpn-manager.service
systemctl start vpn-manager.service
