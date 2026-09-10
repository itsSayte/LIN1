#!/bin/bash
# ==============================================================================
# Nom du fichier : SRV-LIN1-02.sh
# Description    : Automation of Installation, Service Setup, and Server Configuration 02
# Auteur         : Le Normand Thibault
# Date           : 03.09.2026
# Version        : 1.0.0
# ==============================================================================

set -e
ip route del default
ip route add default via 10.10.10.11



# Setup network configuration using nmcli
echo ">>= Setup networking =<<"
apt install network-manager -y
nmcli connection add \
    type ethernet \
    con-name "ens34" \
    ifname ens34 \
    ipv4.method manual \
    ipv4.addresses 10.10.10.22/24 \
    ipv4.gateway 10.10.10.11 \
    ipv4.dns "10.10.10.11"
# Restart network services
systemctl restart networking