#!/bin/bash
# This Script configs strongswan and Quagga on Centos 7
# CHANGE THE VARIABLES BELOW
HOSTNAME="TEST-GW01"
TUNNEL_NAME="shanghai-hq"
TUNNEL_ID="vti11"
TUNNEL_LOCAL_IP="192.168.222.1"
TUNNEL_PEER_IP="192.168.222.2"
ETH0_IP="10.101.1.87"
ETH0_PUBLIC="3.123.254.173"
REMOTE_PEER_IP="210.13.83.19"
MARK="11"
PSK="ScarFace14!"

FIRST_RUN=1

# Install and Configure Strongswan
if ! [ $(find /etc/strongswan/ipsec.conf) ] ;  then
yum install -y epel-release
yum install strongswan -y
fi

if [ $(find /etc/sysconfig/network-scripts/ -name ifcfg-$TUNNEL_ID) ] ;  then
echo "interface already exists"
FIRST_RUN=0
else
echo 'Configuring interface'
echo "DEVICE=$TUNNEL_ID
BOOTPROTO=none
ONBOOT=yes
TYPE=IPIP
PEER_INNER_IPADDR=$TUNNEL_PEER_IP
PEER_OUTER_IPADDR=$REMOTE_PEER_IP
MY_INNER_IPADDR=$TUNNEL_LOCAL_IP
dpdaction=restart
keyexchange=ikev2
MTU=1400" > /etc/sysconfig/network-scripts/ifcfg-$TUNNEL_ID
fi

if [ $FIRST_RUN -eq 1 ] ; then
echo net.ipv4.conf.$TUNNEL_ID.disable_policy=1 >> /etc/sysctl.conf 
sysctl -p

echo "configuring tunnel"
echo "conn $TUNNEL_NAME
  left=$ETH0_IP
  leftid=$ETH0_PUBLIC
  leftsubnet=0.0.0.0/0
  right=$REMOTE_PEER_IP
  rightid=$REMOTE_PEER_IP
  rightsubnet=0.0.0.0/0
  auto=start
  authby=secret
  keyexchange=ikev2
  dpdaction=restart
  mark=$MARK" > /etc/ipsec.d/$TUNNEL_NAME.conf 
  
echo $ETH0_PUBLIC $REMOTE_PEER_IP : PSK $PSK >> /etc/strongswan/ipsec.secrets

if [ $(find /etc/strongswan/ipsec.conf) ] ;  then
strongswan update
strongswan up $TUNNEL_NAME
else
echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf 
echo net.ipv4.conf.all.rp_filter = 2 >> /etc/sysctl.conf 
echo include /etc/strongswan/ipsec.d/*.conf >> /etc/ipsec.con
sed -i 's/# install_routes = yes/install_routes = no/g' /etc/strongswan/strongswan.d/charon.conf
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
systemctl enable --now strongswan
sysctl -p
fi

ip tunnel add $TUNNEL_ID local $ETH0_IP remote $REMOTE_PEER_IP mode vti key $MARK
ifup $TUNNEL_ID
chmod +x /etc/rc.d/rc.local
echo ip tunnel add $TUNNEL_ID local $ETH0_IP remote $REMOTE_PEER_IP mode vti key $MARK >> /etc/rc.d/rc.local

else 
echo "Running this script again could cause issues, exiting script"
fi

# Install Quagga
if ! [ $(find /etc/quagga/zebra.conf) ] ;  then
yum install quagga-0.99.22.4 -y
cp /usr/share/doc/quagga-0.99.22.4/zebra.conf.sample /etc/quagga/zebra.conf
cp /usr/share/doc/quagga-0.99.22.4/bgpd.conf.sample /etc/quagga/bgpd.conf
systemctl start zebra
systemctl enable zebra
systemctl start bgpd
systemctl enable bgpd
chmod -R 777 /etc/quagga/
#setsebool zebra_write_config=1
fi

#echo $HOSTNAME >> /etc/hostname
#hostname $HOSTNAME