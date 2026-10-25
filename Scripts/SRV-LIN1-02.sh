#!/bin/bash

###############################################################################
# SRV-LIN1-02.sh
#
# Auteur : Thibault Le Normand
#
# Installation :
# - Réseau
# - Apache
# - MariaDB
# - PHP
# - Nextcloud
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

NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_DB_PASSWORD="Pa\$\$w0rd"

###############################################################################
# VERIFICATION ROOT
###############################################################################

if [ "$EUID" -ne 0 ]; then
    echo "Veuillez exécuter ce script en root."
    exit 1
fi

###############################################################################
# CONFIGURATION HOSTNAME
###############################################################################

echo "[+] Configuration hostname"

hostnamectl set-hostname SRV-LIN1-02

###############################################################################
# CONFIGURATION HOSTS
###############################################################################

cat > /etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 SRV-LIN1-02

10.10.10.11 srv-lin1-01.LIN09.local srv-lin1-01
10.10.10.22 srv-lin1-02.LIN09.local srv-lin1-02
10.10.10.33 nas-lin1-01.LIN09.local nas-lin1-01
EOF

###############################################################################
# CONFIGURATION DNS CLIENT
###############################################################################

cat > /etc/resolv.conf << EOF
search LIN09.local
nameserver ${DNS_SERVER}
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
    address ${SERVER_IP}/24
EOF

###############################################################################
# TEST RESEAU
###############################################################################

ping -c 2 ${DNS_SERVER}

###############################################################################
# MISE A JOUR
###############################################################################

apt update
apt upgrade -y

###############################################################################
# INSTALLATION APACHE
###############################################################################

apt install -y apache2

systemctl enable apache2
systemctl restart apache2

###############################################################################
# INSTALLATION PHP
###############################################################################

apt install -y \
php \
php-cli \
php-common \
php-gd \
php-curl \
php-zip \
php-xml \
php-mbstring \
php-intl \
php-imagick \
php-bz2 \
php-mysql \
libapache2-mod-php

###############################################################################
# INSTALLATION MARIADB
###############################################################################

apt install -y mariadb-server

systemctl enable mariadb
systemctl restart mariadb

###############################################################################
# CREATION BASE NEXTCLOUD
###############################################################################

mysql << EOF
CREATE DATABASE nextcloud;
CREATE USER 'nextcloud'@'localhost'
IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
EOF

###############################################################################
# TELECHARGEMENT NEXTCLOUD
###############################################################################

cd /tmp

wget https://download.nextcloud.com/server/releases/latest.zip

apt install -y unzip

unzip latest.zip

mv nextcloud /var/www/

###############################################################################
# PERMISSIONS
###############################################################################

chown -R www-data:www-data /var/www/nextcloud

###############################################################################
# CONFIGURATION APACHE
###############################################################################

cat > /etc/apache2/sites-available/nextcloud.conf << EOF
<VirtualHost *:80>

    ServerName srv-lin1-02.${DOMAIN}

    DocumentRoot /var/www/nextcloud

    <Directory /var/www/nextcloud>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>

</VirtualHost>
EOF

a2enmod rewrite
a2enmod headers
a2enmod env
a2enmod dir
a2enmod mime

a2ensite nextcloud.conf

systemctl reload apache2

###############################################################################
# CLIENT LDAP
###############################################################################

apt install -y ldap-utils

###############################################################################
# ETAT DES SERVICES
###############################################################################

echo ""
echo "======================================="
echo "NEXTCLOUD"
echo "======================================="
echo ""
echo "URL : http://${SERVER_IP}"
echo ""
echo "Base de données : nextcloud"
echo "Utilisateur SQL : nextcloud"
echo "Mot de passe SQL : ${NEXTCLOUD_DB_PASSWORD}"
echo ""
echo "LDAP : ${DNS_SERVER}"
echo ""
echo "======================================="