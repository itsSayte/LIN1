#!/bin/bash
# ==============================================================================
# Nom du fichier : SRV-LIN1-01.sh
# Description    : Automation of Installation, Service Setup, and Server Configuration 01
# Auteur         : Le Normand Thibault
# Date           : 20.08.2026
# Version        : 1.0.0
# ==============================================================================

# stop on error
set -e
# update packages
echo ">>= Update of packages =<<"
apt update -y
apt-get update -y
# Install services DHCP, DNS, LDAP et VIM
echo ">>= Download packages =<<"
apt-get install kea-dhcp4-server ldap-account-manager -y
apt install bind9 bind9utils bind9-doc bind9-host dnsutils slapd ldap-utils vim iptables-persistent -y


echo ">>= Backup of configurations files =<<"
cp -n /etc/bind/named.conf /etc/bind/named.conf.bak
cp -n /etc/bind/named.conf.local /etc/bind/named.conf.local.bak
cp -n /etc/bind/named.conf.options /etc/bind/named.conf.options.bak
# Enter the ldap admin

# Setup network configuration using nmcli
echo ">>= Setup networking =<<"
apt install network-manager -y
nmcli connection add \
    type ethernet \
    con-name "ens34" \
    ifname ens34 \
    ipv4.method manual \
    ipv4.addresses 10.10.10.11/24 \
    ipv4.gateway 10.10.10.1 \
    ipv4.dns "10.10.10.11"
# Restart network services
systemctl restart networking

# Configure global BIND options
echo ">>= Configuring named.conf.options =<<"
cat > /etc/bind/named.conf.options << 'EOF'
options {
        directory "/var/cache/bind";

        recursion yes;

        allow-query { any; };

        allow-recursion {
                127.0.0.1;
                10.10.10.0/24;
        };

        forwarders {
                192.168.133.2;
                };

        dnssec-validation no;
};
EOF

# Declare forward and reverse lookup zones
echo ">>= Configuring DNS zones =<<"
cat > /etc/bind/named.conf.local << 'EOF'
zone "LIN09.local" {
        type master;
        file "/etc/bind/db.LIN09.local";
};

zone "10.10.10.in-addr.arpa" {
        type master;
        file "/etc/bind/db.10.10.10";
};
EOF

# Create the forward zone file
echo ">>= Creating forward lookup zone file =<<"
cat > /etc/bind/db.LIN09.local << 'EOF'
$TTL 604800
@       IN      SOA     srv-lin1-01.LIN09.local. root.LIN09.local. (
                        2
                        604800
                        86400
                        2419200
                        604800 )

@               IN      NS      srv-lin1-01.LIN09.local.
srv-lin1-01     IN      A       10.10.10.11
EOF

# Create the reverse zone file
echo ">>= Creating reverse lookup zone file =<<"
cat > /etc/bind/db.10.10.10 << 'EOF'
$TTL 604800
@       IN      SOA     srv-lin1-01.LIN09.local. root.LIN09.local. (
                        2
                        604800
                        86400
                        2419200
                        604800 )

@       IN      NS      srv-lin1-01.LIN09.local.
11      IN      PTR     srv-lin1-01.LIN09.local.
EOF


echo ">>= Setting file ownership =<<"
chown bind:bind /etc/bind/db.LIN09.local
chown bind:bind /etc/bind/db.10.10.10


echo ">>= Checking BIND configuration syntax =<<"
named-checkconf


echo ">>= Validating forward lookup zone =<<"
named-checkzone LIN09.local /etc/bind/db.LIN09.local


echo ">>= Validating reverse lookup zone =<<"
named-checkzone 10.10.10.in-addr.arpa /etc/bind/db.10.10.10

echo ">>= Restarting DNS service =<<"
systemctl restart bind9

echo ">>= DNS configuration completed successfully =<<"

echo ">>= Start DHCP Configuration=<<"

echo ">>= Creating backup of current configuration =<<"
cp -f /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.bak 2>/dev/null || true

echo ">>= Creating DHCP configuration =<<"

cat > /etc/kea/kea-dhcp4.conf << 'EOF'
{
  "Dhcp4": {

    "interfaces-config": {
      "interfaces": [ "ens34" ]
    },

    "control-socket": {
      "socket-type": "unix",
      "socket-name": "/run/kea/kea4-ctrl-socket"
    },

    "lease-database": {
      "type": "memfile",
      "lfc-interval": 3600
    },

    "valid-lifetime": 600,
    "max-valid-lifetime": 7200,

    "subnet4": [
      {
        "id": 1,

        "subnet": "10.10.10.0/24",

        "pools": [
          {
            "pool": "10.10.10.100 - 10.10.10.200"
          }
        ],

        "option-data": [
          {
            "name": "routers",
            "data": "10.10.10.11"
          },
          {
            "name": "domain-name-servers",
            "data": "10.10.10.11"
          },
          {
            "name": "domain-name",
            "data": "LIN09.local"
          }
        ]
      }
    ]
  }
}
EOF

echo ">>= Checking configuration syntax =<<"
kea-dhcp4 -t /etc/kea/kea-dhcp4.conf

echo ">>= Enabling DHCP service =<<"
systemctl enable kea-dhcp4-server

echo ">>= Restarting DHCP service =<<"
systemctl restart kea-dhcp4-server

echo ">>= Displaying service status =<<"
systemctl status kea-dhcp4-server --no-pager

echo ">>= Checking DHCP listening port =<<"
ss -lunp | grep 67 || true

echo ">>= Installation completed successfully =<<"
echo "DHCP Pool     : 10.10.10.100 - 10.10.10.200"
echo "Gateway       : 10.10.10.254"
echo "DNS Server    : 10.10.10.11"
echo "DNS Domain    : LIN09.local"
echo "Interface     : ens34"


echo ">>= Start LDAP Configuration"
BASE_DN="dc=lin09,dc=local"
ADMIN_DN="cn=admin,$BASE_DN"

echo ">>= Generating LDAP password hash =<<"

LDAP_HASH=$(slappasswd -s "Pa\$\$w0rd")

echo ">>= Creating organizational units =<<"

cat > /tmp/base.ldif << EOF
dn: ou=People,$BASE_DN
objectClass: organizationalUnit
ou: People

dn: ou=Groups,$BASE_DN
objectClass: organizationalUnit
ou: Groups
EOF

echo ">>= Creating groups =<<"

cat > /tmp/groups.ldif << EOF
dn: cn=managers,ou=Groups,$BASE_DN
objectClass: posixGroup
cn: managers
gidNumber: 10001

dn: cn=ingenieurs,ou=Groups,$BASE_DN
objectClass: posixGroup
cn: ingenieurs
gidNumber: 10002

dn: cn=developpeurs,ou=Groups,$BASE_DN
objectClass: posixGroup
cn: developpeurs
gidNumber: 10003

dn: cn=logiciels,ou=Groups,$BASE_DN
objectClass: posixGroup
cn: logiciels
gidNumber: 10004
EOF

echo ">>= Creating users =<<"

cat > /tmp/users.ldif << EOF
dn: uid=man01,ou=People,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Manager 01
sn: Manager
uid: man01
uidNumber: 11001
gidNumber: 10001
homeDirectory: /home/man01
loginShell: /bin/bash
userPassword: $LDAP_HASH

dn: uid=man02,ou=People,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Manager 02
sn: Manager
uid: man02
uidNumber: 11002
gidNumber: 10001
homeDirectory: /home/man02
loginShell: /bin/bash
userPassword: $LDAP_HASH

dn: uid=ing01,ou=People,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Ingenieur 01
sn: Ingenieur
uid: ing01
uidNumber: 11003
gidNumber: 10002
homeDirectory: /home/ing01
loginShell: /bin/bash
userPassword: $LDAP_HASH

dn: uid=ing02,ou=People,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Ingenieur 02
sn: Ingenieur
uid: ing02
uidNumber: 11004
gidNumber: 10002
homeDirectory: /home/ing02
loginShell: /bin/bash
userPassword: $LDAP_HASH

dn: uid=dev01,ou=People,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Developpeur 01
sn: Developpeur
uid: dev01
uidNumber: 11005
gidNumber: 10003
homeDirectory: /home/dev01
loginShell: /bin/bash
userPassword: $LDAP_HASH
EOF

echo ">>= Importing organizational units =<<"
ldapadd -x -D "$ADMIN_DN" -W -f /tmp/base.ldif

echo ">>= Importing groups =<<"
ldapadd -x -D "$ADMIN_DN" -W -f /tmp/groups.ldif

echo ">>= Importing users =<<"
ldapadd -x -D "$ADMIN_DN" -W -f /tmp/users.ldif

echo "Displaying LDAP users"
ldapsearch -x -LLL -b "ou=People,$BASE_DN" uid

echo "Displaying LDAP groups"
ldapsearch -x -LLL -b "ou=Groups,$BASE_DN" cn

echo "OpenLDAP configuration completed successfully"

echo "Configuration IP route"

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
# Enable NAT
iptables -t nat -A POSTROUTING -o ens33 -j MASQUERADE
# Enable Forwarding
sudo iptables -t nat -A POSTROUTING -o ens33 -j MASQUERADE
sudo iptables -A FORWARD -i ens34 -o ens33 -j ACCEPT
sudo iptables -A FORWARD -i ens33 -o ens34 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo netfilter-persistent save

