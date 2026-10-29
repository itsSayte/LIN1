#!/bin/bash

###############################################################################
# SRV-LIN1-02.sh
#
# Auteur : Thibault 
#
# Projet LIN1
#
# Configuration :
# - Réseau
# - Hostname
# - SSH
# - Apache
# - PHP
# - MariaDB
# - Nextcloud
# - NFS
#
###############################################################################

set -e

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

###############################################################################
# VARIABLES
###############################################################################

DOMAIN="LIN09.local"

WAN_IF="ens33"
LAN_IF="ens37"

SERVER_IP="10.10.10.22"
DNS_SERVER="10.10.10.11"
GATEWAY="10.10.10.11"

NEXTCLOUD_PATH="/var/www/nextcloud"

DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASSWORD='Pa$$w0rd'

###############################################################################
# ROOT
###############################################################################

if [ "$EUID" -ne 0 ]; then
    echo "Veuillez lancer le script en root."
    exit 1
fi

###############################################################################
# RESEAU
###############################################################################

cat > /etc/network/interfaces << EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

allow-hotplug ${WAN_IF}
iface ${WAN_IF} inet dhcp

auto ${LAN_IF}
iface ${LAN_IF} inet static
    address ${SERVER_IP}/24
    gateway ${GATEWAY}
EOF

ip link set ${LAN_IF} up

###############################################################################
# ATTENTE RESEAU
###############################################################################

echo "[+] Attente du réseau"

until ping -c 1 ${DNS_SERVER} >/dev/null 2>&1
do
    sleep 2
done

###############################################################################
# HOSTNAME
###############################################################################

hostnamectl set-hostname SRV-LIN1-02

###############################################################################
# HOSTS
###############################################################################

cat > /etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 SRV-LIN1-02

10.10.10.11 srv-lin1-01.${DOMAIN} srv-lin1-01
10.10.10.22 srv-lin1-02.${DOMAIN} srv-lin1-02
10.10.10.33 nas-lin1-01.${DOMAIN} nas-lin1-01

::1 localhost ip6-localhost ip6-loopback
EOF

###############################################################################
# UPDATE
###############################################################################

apt update
apt upgrade -y

###############################################################################
# SSH
###############################################################################

apt install -y openssh-server

systemctl enable ssh
systemctl restart ssh

mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f /root/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
fi

###############################################################################
# APACHE
###############################################################################

apt install -y apache2

systemctl enable apache2

###############################################################################
# PHP
###############################################################################

apt install -y \
php \
libapache2-mod-php \
php-cli \
php-common \
php-gd \
php-curl \
php-xml \
php-zip \
php-mbstring \
php-intl \
php-bz2 \
php-imagick \
php-mysql \
php-ldap \
php-bcmath \
php-gmp

###############################################################################
# MARIADB
###############################################################################

apt install -y mariadb-server

systemctl enable mariadb
systemctl restart mariadb

###############################################################################
# BASE NEXTCLOUD
###############################################################################

mysql << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES
ON ${DB_NAME}.*
TO '${DB_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF

###############################################################################
# NEXTCLOUD
###############################################################################

apt install -y wget unzip

mkdir -p /opt/install

cd /opt/install

wget -O nextcloud.zip \
https://download.nextcloud.com/server/releases/latest.zip

unzip -o nextcloud.zip

rm -f nextcloud.zip

rm -rf ${NEXTCLOUD_PATH}

mv nextcloud ${NEXTCLOUD_PATH}

chown -R www-data:www-data ${NEXTCLOUD_PATH}

###############################################################################
# APACHE VHOST
###############################################################################

cat > /etc/apache2/sites-available/nextcloud.conf << EOF
<VirtualHost *:80>

    ServerName srv-lin1-02.${DOMAIN}

    DocumentRoot ${NEXTCLOUD_PATH}

    <Directory ${NEXTCLOUD_PATH}>
        AllowOverride All
        Require all granted
    </Directory>

</VirtualHost>
EOF

a2dissite 000-default.conf || true

a2enmod rewrite
a2enmod headers
a2enmod env
a2enmod dir
a2enmod mime

###############################################################################
# HTTPS
###############################################################################

a2enmod ssl

openssl req -x509 -nodes -days 365 \
-newkey rsa:2048 \
-keyout /etc/ssl/private/nextcloud.key \
-out /etc/ssl/certs/nextcloud.crt \
-subj "/CN=srv-lin1-02"

cat > /etc/apache2/sites-available/nextcloud-ssl.conf << EOF
<VirtualHost *:443>

    ServerName srv-lin1-02.${DOMAIN}

    DocumentRoot ${NEXTCLOUD_PATH}

    SSLEngine on

    SSLCertificateFile /etc/ssl/certs/nextcloud.crt
    SSLCertificateKeyFile /etc/ssl/private/nextcloud.key

    <Directory ${NEXTCLOUD_PATH}>
        AllowOverride All
        Require all granted
    </Directory>

</VirtualHost>
EOF

a2ensite nextcloud.conf
a2ensite nextcloud-ssl.conf

systemctl restart apache2

###############################################################################
# LDAP TOOLS
###############################################################################

apt install -y ldap-utils

###############################################################################
# NFS
###############################################################################

apt install -y nfs-common acl

mkdir -p /mnt/Commun
mkdir -p /mnt/Clients
mkdir -p /mnt/Logiciels
mkdir -p /mnt/Perso

grep -q "/mnt/Commun" /etc/fstab || cat >> /etc/fstab << EOF

10.10.10.33:/export/Commun     /mnt/Commun     nfs defaults,_netdev 0 0
10.10.10.33:/export/Clients    /mnt/Clients    nfs defaults,_netdev 0 0
10.10.10.33:/export/Logiciels  /mnt/Logiciels  nfs defaults,_netdev 0 0
10.10.10.33:/export/Perso      /mnt/Perso      nfs defaults,_netdev 0 0
EOF

mount -a

###############################################################################
# VERIFICATIONS
###############################################################################

echo ""
echo "=================================================="
echo "VERIFICATIONS"
echo "=================================================="

echo ""
echo "[DNS]"
nslookup srv-lin1-01.${DOMAIN}

echo ""
echo "[APACHE]"
systemctl is-active apache2

echo ""
echo "[MARIADB]"
systemctl is-active mariadb

echo ""
echo "[SSH]"
systemctl is-active ssh

echo ""
echo "[HTTPS]"
ss -tulpn | grep 443 || true

echo ""
echo "[NFS]"
mount | grep nfs || true

echo ""
echo "[NEXTCLOUD]"
ls ${NEXTCLOUD_PATH}

echo ""
echo "=================================================="
echo "DEPLOIEMENT TERMINE"
echo "=================================================="

echo ""
echo "Accès Nextcloud :"
echo "https://${SERVER_IP}"
echo ""
echo "Base de données :"
echo "Nom : ${DB_NAME}"
echo "Utilisateur : ${DB_USER}"
echo ""
echo "Configuration manuelle restante :"
echo "  - Création du compte administrateur Nextcloud"
echo "  - Configuration LDAP"
echo "  - Configuration des stockages externes"
echo ""