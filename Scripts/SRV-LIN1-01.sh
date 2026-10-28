#!/bin/bash

###############################################################################
# SRV-LIN1-01.sh
#
# Auteur : Thibault Le Normand
# Projet LIN1
#
# Configuration automatique de :
# - Réseau
# - Hostname
# - Routage IPv4
# - NAT
# - DNS (Bind9)
# - DHCP (Kea DHCP)
# - LDAP (OpenLDAP)
#
###############################################################################

set -e

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' > /root/.bashrc

###############################################################################
# VARIABLES
###############################################################################

DOMAIN="LIN09.local"

# Interfaces réseau
WAN_IF="ens33"
LAN_IF="ens37"

# Adresse réseau locale
LAN_IP="10.10.10.11"

# LDAP
LDAP_ADMIN="cn=admin,dc=LIN09,dc=local"

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

###############################################################################
# VERIFICATION DES PRIVILEGES
###############################################################################

if [ "$EUID" -ne 0 ]; then
    echo "Veuillez exécuter ce script avec sudo."
    exit 1
fi

###############################################################################
# FORCER APT A UTILISER IPV4
###############################################################################

echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
apt update

###############################################################################
# MISE A JOUR DU SYSTEME
###############################################################################

echo "[+] Mise à jour du système"

apt update
apt upgrade -y

###############################################################################
# CONFIGURATION DU NOM D'HOTE
###############################################################################

echo "[+] Configuration du hostname"

hostnamectl set-hostname SRV-LIN1-01

###############################################################################
# CONFIGURATION DU FICHIER HOSTS
###############################################################################

echo "[+] Configuration du fichier hosts"

cat > /etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       SRV-LIN1-01

10.10.10.11     srv-lin1-01.LIN09.local srv-lin1-01
10.10.10.22     srv-lin1-02.LIN09.local srv-lin1-02
10.10.10.33     nas-lin1-01.LIN09.local nas-lin1-01

::1             localhost ip6-localhost ip6-loopback
EOF

###############################################################################
# CONFIGURATION RESEAU
###############################################################################

cat > /etc/network/interfaces << EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

allow-hotplug ${WAN_IF}
iface ${WAN_IF} inet dhcp

auto ${LAN_IF}
iface ${LAN_IF} inet static
    address ${LAN_IP}/24
EOF

# Pas de restart networking ici


###############################################################################
# VERIFICATION RESEAU
###############################################################################

echo "[+] Vérification réseau"

ip a
ip route

ping -c 2 8.8.8.8

getent hosts deb.debian.org

###############################################################################
# ACTIVATION DU ROUTAGE IPV4
###############################################################################

echo "[+] Activation du routage IPv4"

cat > /etc/sysctl.d/99-routing.conf << EOF
net.ipv4.ip_forward=1
EOF

sudo sysctl --system





###############################################################################
# INSTALLATION NAT
###############################################################################

echo "[+] Installation d'iptables"

apt install -y iptables iptables-persistent

###############################################################################
# CONFIGURATION NAT
###############################################################################

echo "[+] Configuration du NAT"

# Traduction d'adresse afin de permettre
# au réseau LAN d'accéder à Internet

sudo iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE

# Autorise les connexions sortantes du LAN

sudo iptables -A FORWARD -i ${LAN_IF} -o ${WAN_IF} -j ACCEPT

# Autorise les réponses provenant d'Internet

sudo iptables -A FORWARD \
-i ${WAN_IF} \
-o ${LAN_IF} \
-m conntrack \
--ctstate RELATED,ESTABLISHED \
-j ACCEPT

# Sauvegarde des règles

sudo iptables-save > /etc/iptables/rules.v4

###############################################################################
# INSTALLATION DNS
###############################################################################

echo "[+] Installation de Bind9"

apt install -y bind9 bind9-utils bind9-doc dns-root-data

###############################################################################
# CONFIGURATION DNS RECURSIF
###############################################################################

echo "[+] Configuration des forwarders DNS"

cat > /etc/bind/named.conf.options << EOF
options {
        directory "/var/cache/bind";

        recursion yes;
        allow-recursion { any; };
        allow-query { any; };

        forwarders {
                192.168.28.2;
        };

        dnssec-validation no;

        listen-on { any; };
        listen-on-v6 { any; };
};
EOF


###############################################################################
# CONFIGURATION DES ZONES DNS
###############################################################################

echo "[+] Création des zones DNS"

cat > /etc/bind/named.conf.local << EOF
zone "${DOMAIN}" {
    type master;
    file "/etc/bind/db.${DOMAIN}";
};

zone "10.10.10.in-addr.arpa" {
    type master;
    file "/etc/bind/db.10.10.10";
};
EOF

###############################################################################
# ZONE DNS DIRECTE
###############################################################################

cat > /etc/bind/db.${DOMAIN} << EOF
\$TTL 604800

@ IN SOA srv-lin1-01.${DOMAIN}. root.${DOMAIN}. (
        1
        604800
        86400
        2419200
        604800 )

@ IN NS srv-lin1-01.${DOMAIN}.

srv-lin1-01 IN A 10.10.10.11
srv-lin1-02 IN A 10.10.10.22
nas-lin1-01 IN A 10.10.10.33
EOF

###############################################################################
# ZONE DNS INVERSE
###############################################################################

cat > /etc/bind/db.10.10.10 << EOF
\$TTL 604800

@ IN SOA srv-lin1-01.${DOMAIN}. root.${DOMAIN}. (
        1
        604800
        86400
        2419200
        604800 )

@ IN NS srv-lin1-01.${DOMAIN}.

11 IN PTR srv-lin1-01.${DOMAIN}.
22 IN PTR srv-lin1-02.${DOMAIN}.
33 IN PTR nas-lin1-01.${DOMAIN}.
EOF

###############################################################################
# VERIFICATION DNS
###############################################################################

echo "[+] Vérification DNS"

named-checkconf

named-checkzone \
${DOMAIN} \
/etc/bind/db.${DOMAIN}

named-checkzone \
10.10.10.in-addr.arpa \
/etc/bind/db.10.10.10

###############################################################################
# DEMARRAGE DNS
###############################################################################

systemctl enable named
systemctl restart named

###############################################################################
# INSTALLATION DHCP
###############################################################################

echo "[+] Installation du serveur DHCP"

apt install -y kea-dhcp4-server

###############################################################################
# CONFIGURATION DHCP
###############################################################################

cat > /etc/kea/kea-dhcp4.conf << EOF
{
 "Dhcp4": {

  "interfaces-config": {
   "interfaces": [ "${LAN_IF}" ]
  },

  "lease-database": {
   "type": "memfile"
  },

  "valid-lifetime": 3600,

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
###############################################################################
# VERIFICATION DHCP
###############################################################################

echo "[+] Vérification DHCP"

systemctl enable kea-dhcp4-server
systemctl restart kea-dhcp4-server

sleep 2

systemctl is-active kea-dhcp4-server

journalctl -u kea-dhcp4-server -n 10 --no-pager


###############################################################################
# DEMARRAGE DHCP
###############################################################################

systemctl enable kea-dhcp4-server
systemctl restart kea-dhcp4-server

sleep 2

systemctl --no-pager --full status kea-dhcp4-server
###############################################################################
# INSTALLATION LDAP
###############################################################################


LDAP_DOMAIN="LIN09.local"
LDAP_ORG="Lin1-LABO"
LDAP_ADMIN="cn=admin,dc=LIN09,dc=local"
LDAP_ADMIN_PASSWORD='Pa$$w0rd'
LDAP_PASSWORD="${LDAP_ADMIN_PASSWORD}"

###############################################################################
# PRECONFIGURATION DE SLAPD
###############################################################################

# Préconfiguration de slapd
debconf-set-selections << EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORG}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF

###############################################################################
# INSTALLATION LDAP
###############################################################################

echo "[+] Installation du serveur LDAP"

DEBIAN_FRONTEND=noninteractive apt install -y slapd ldap-utils

###############################################################################
# IMPORT DE LA STRUCTURE LDAP
###############################################################################

echo "[+] Import des OU"

ldapadd -x \
-D "${LDAP_ADMIN}" \
-w "${LDAP_PASSWORD}" \
-f "${SCRIPT_DIR}/LDAP_ldif/base.ldif"

###############################################################################
# IMPORT DES GROUPES LDAP
###############################################################################

echo "[+] Import des groupes"

ldapadd -x \
-D "${LDAP_ADMIN}" \
-w "${LDAP_PASSWORD}" \
-f "${SCRIPT_DIR}/LDAP_ldif/groups.ldif"

###############################################################################
# IMPORT DES UTILISATEURS LDAP
###############################################################################

echo "[+] Import des utilisateurs"

ldapadd -x \
-D "${LDAP_ADMIN}" \
-w "${LDAP_PASSWORD}" \
-f "${SCRIPT_DIR}/LDAP_ldif/users.ldif"

###############################################################################
# DEMARRAGE LDAP
###############################################################################

systemctl enable slapd
systemctl restart slapd

###############################################################################
# VERIFICATION LDAP
###############################################################################

echo "[+] Vérification LDAP"

ldapwhoami -x \
-D "${LDAP_ADMIN}" \
-w "${LDAP_PASSWORD}"

ldapsearch -x -LLL \
-b dc=LIN09,dc=local

ldapsearch -x -LLL \
-b dc=LIN09,dc=local \
"(uid=dev01)"




###############################################################################
# INSTALLATION APACHE
###############################################################################

echo "[+] Installation Apache"

apt install -y apache2

systemctl enable apache2
systemctl restart apache2


###############################################################################
# INSTALLATION LDAP ACCOUNT MANAGER (LAM)
###############################################################################

echo "[+] Installation de LDAP Account Manager"

apt install -y ldap-account-manager


LAM_CONF="/var/lib/ldap-account-manager/config/lam.conf"

sed -i 's|"Admins": "cn=Manager,dc=my-domain,dc=com"|"Admins": "cn=admin,dc=LIN09,dc=local"|' "$LAM_CONF"

sed -i 's|"loginSearchSuffix": "dc=yourdomain,dc=org"|"loginSearchSuffix": "dc=LIN09,dc=local"|' "$LAM_CONF"

sed -i 's|"suffix_user": "ou=People,dc=my-domain,dc=com"|"suffix_user": "ou=People,dc=LIN09,dc=local"|' "$LAM_CONF"

sed -i 's|"suffix_group": "ou=group,dc=my-domain,dc=com"|"suffix_group": "ou=Groups,dc=LIN09,dc=local"|' "$LAM_CONF"

sed -i 's|"treeViewSuffix": "dc=yourdomain,dc=org"|"treeViewSuffix": "dc=LIN09,dc=local"|' "$LAM_CONF"

chown www-data:root "$LAM_CONF"
chmod 600 "$LAM_CONF"

systemctl restart apache2

###############################################################################
# ACTIVATION DES MODULES APACHE NECESSAIRES
###############################################################################

/usr/sbin/a2enmod ssl
/usr/sbin/a2enmod rewrite

###############################################################################
# REDÉMARRAGE D'APACHE
###############################################################################

systemctl restart apache2

###############################################################################
# INFORMATIONS LAM
###############################################################################

echo ""
echo "=================================================="
echo "LDAP ACCOUNT MANAGER"
echo "=================================================="
echo ""
echo "URL : http://${LAN_IP}/lam"
echo ""
echo "Configuration du profil LAM"
echo ""
echo "Server address  : ldap://localhost:389"
echo "Valid users     : cn=admin,dc=LIN09,dc=local"
echo "Tree suffix     : dc=LIN09,dc=local"
echo "Users suffix    : ou=People,dc=LIN09,dc=local"
echo "Groups suffix   : ou=Groups,dc=LIN09,dc=local"
echo ""
echo "Mot de passe LDAP : ${LDAP_PASSWORD}"
echo ""

###############################################################################
# ETAT DES SERVICES
###############################################################################

echo ""
echo "=================================================="
echo "ETAT DES SERVICES"
echo "=================================================="

echo ""
echo "Bind9 :"
systemctl is-active named

echo ""
echo "Kea DHCP :"
systemctl is-active kea-dhcp4-server

echo ""
echo "OpenLDAP :"
systemctl is-active slapd

echo ""
echo "WAN : ${WAN_IF}"
echo "LAN : ${LAN_IF}"

echo ""
echo "=================================================="
echo "CONFIGURATION TERMINEE"
echo "=================================================="

echo ""
echo "Tests recommandés :"
echo "nslookup srv-lin1-02.${DOMAIN}"
echo "nslookup nas-lin1-01.${DOMAIN}"
echo "ldapsearch -x -LLL -b dc=LIN09,dc=local"
echo "iptables -t nat -L -n -v"
echo ""
