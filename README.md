# Documentation technique LIN1

## Introduction

### Objectifs

L'objectif du projet est de mettre en place une infrastructure réseau complète basée sur linux permettant :

- La gestion des utilisateurs via LDAP
- La résolution DNS
- L'attribution dynamique d'adresses IP
- Le stockage réseau centralisé
- La synchronisation des données avec Nextcloud

### Architecture

| Machine     | Adresse IP  | Fonction                   |
| ----------- | ----------- | -------------------------- |
| SRV-LIN1-01 | 10.10.10.11 | DNS, DHCP, LDAP, Routage   |
| SRV-LIN1-02 | 10.10.10.22 | Nextcloud                  |
| NAS-LIN1-01 | 10.10.10.33 | OpenMediaVault, RAID1, NFS |

# SRV-LIN1-01

## Présentation

SRV-LIN1-01 est le serveur principal de l'infrastructure.

Il héberge les services suivants :

- DNS (Bind9)

- DHCP (Kea-DHCP)

- LDAP (OpenLDAP)

- Routeur NAT

- Accès Internet pour le LAN

---

# Configuration matérielle

| Ressource         | Valeur             |
| ----------------- | ------------------ |
| RAM               | 1 GO               |
| Disque            | 10 GO              |
| Interfaces réseau | 2 (NAT, Host-Only) |
| OS                | Debian 13          |

---

# Configuration réseau

## Interfaces

### WAN

```text
ens33

DHCP
```

### LAN

```text
ens34

10.10.10.11/24
```

## Vérification

Assurer vous que la configuration est appliquée correctement. vous que la configuration est appliquée correctement.

```bash
ip a

ip route
```

---

# Configuration du routage et du NAT

### Objectif

Le serveur SRV-LIN1-01 agit comme passerelle entre le réseau local `10.10.10.0/24` et Internet. Afin de permettre aux machines du LAN d'accéder aux ressources externes, le routage IPv4 et la traduction d'adresses (NAT) ont été mis en place.

### Activation du routage IPv4

Le routage IPv4 a été activé afin d'autoriser le transfert des paquets entre les interfaces WAN et LAN.

```bash
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-routing.conf

sysctl --system
```

### Configuration du NAT

La traduction d'adresses est réalisée avec `iptables` afin que toutes les machines du réseau local puissent accéder à Internet en utilisant l'adresse IP publique du serveur.

```bash
iptables -t nat -A POSTROUTING -o ens33 -j MASQUERADE

iptables -A FORWARD -i ens34 -o ens33 -j ACCEPT

iptables -A FORWARD -i ens33 -o ens34 \

-m conntrack \

--ctstate RELATED,ESTABLISHED \

-j ACCEPT
```

### Persistance de la configuration

Afin de conserver les règles de pare-feu après un redémarrage du serveur, le paquet `iptables-persistent` a été installé et les règles ont été sauvegardées.

```bash
apt install iptables-persistent

iptables-save > /etc/iptables/rules.v4
```

### Vérification

Contrôle de l'activation du routage :

```bash
sudo sysctl net.ipv4.ip_forward
```

Résultat attendu :

```text
net.ipv4.ip_forward = 1
```

Contrôle des règles NAT :

```bash
iptables -t nat -L -n -v
```

### Validation

Depuis un client du réseau local, les tests suivants permettent de valider le fonctionnement du routage :

```bash
sudo reboot
```

```bash
ping 8.8.8.8
```

```bash
ping google.com
```

Les réponses obtenues confirment que les clients du réseau local peuvent accéder  à Internet via SRV-LIN1-01.

---

# Configuration DNS

### Objectif

Le serveur DNS permet la résolution des noms des machines de l'infrastructure afin d'éviter l'utilisation systématique des adresses IP.

### Domaine

```
LIN09.local
```

## Fichiers de configuration

```
/etc/bind/named.conf.local

/etc/bind/db.LIN09.local

/etc/bind/db.10.10.10
```

### Configuration de la zone directe

Fichier :

```
/etc/bind/db.LIN09.local
```

Contenu :

```
$TTL 604800

@ IN SOA srv-lin1-01.LIN09.local. root.LIN09.local. (

        3

        604800

        86400

        2419200

        604800 )

@               IN NS srv-lin1-01.LIN09.local.

srv-lin1-01     IN A 10.10.10.11

srv-lin1-02     IN A 10.10.10.22

nas-lin1-01     IN A 10.10.10.33
```

### Configuration de la zone inverse

Fichier:

```
/etc/bind/db.10.10.10
```

Contenu:

```
$TTL    604800
@       IN      SOA     srv-lin1-01.LIN09.local. root.LIN09.local. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      srv-lin1-01.LIN09.local.
11      IN      PTR     srv-lin1-01.LIN09.local.
22      IN      PTR     srv-lin1-02.LIN09.local.
33      IN      PTR     nas-lin1-01.LIN09.local.
```

### Validation de la configuration

```bash
named-checkzone LIN09.local /etc/bind/db.LIN09.local
```

Résultat :

```text
zone LIN09.local/IN: loaded serial 3

OK
```

### Redémarrage du service

```bash
systemctl restart bind9
```

### Vérification

```bash
nslookup srv-lin1-02.LIN09.local 10.10.10.11
```

Résultat :

```text
Name: srv-lin1-02.LIN09.local

Address: 10.10.10.22
```

```bash
nslookup nas-lin1-01.LIN09.local 10.10.10.11
```

Résultat :

```text
Name: nas-lin1-01.LIN09.local

Address: 10.10.10.33
```

### Conclusion

La résolution DNS interne est fonctionnelle. Les machines de l'infrastructure peuvent être jointes à l'aide de leur nom de domaine plutôt qu'à l'aide de leur adresse IP.

---

# Service DHCP

## Présentation

Le serveur DHCP a été installé sur **SRV-LIN1-01** à l'aide de **Kea DHCP Server**.

Son rôle est d'attribuer automatiquement les paramètres réseau aux clients du réseau local.

## Installation

```bash
apt install kea-dhcp4-server
```

## Fichier de configuration

```
/etc/kea/kea-dhcp4.conf
```

## Configuration

Fichier de configuration :

```
/etc/kea/kea-dhcp4.conf
```

Configuration appliquée :

- Réseau : `10.10.10.0/24`

- Plage DHCP : `10.10.10.100 - 10.10.10.200`

- Passerelle : `10.10.10.11`

- DNS : `10.10.10.11`

- Domaine : `LIN09.local`

## Démarrage du service

```bash
systemctl enable kea-dhcp4-server

systemctl restart kea-dhcp4-server
```

## Validation

Vérification sur un client :

```bash
ip a
```

Obtention automatique d'une adresse IP entre :

```
10.10.10.100 - 10.10.10.200
```

Vérification de la passerelle :

```bash
ip route
```

Résultat attendu :

```
default via 10.10.10.11
```

## Dépannage

État du service :

```bash
systemctl status kea-dhcp4-server
```

Consultation des journaux :

```bash
journalctl -u kea-dhcp4-server
```

## Conclusion

Le serveur DHCP permet l'attribution automatique des paramètres réseau aux clients du réseau local et simplifie leur intégration dans l'infrastructure.

# Service LDAP

## Fonction

Le serveur LDAP a été mis en place sur **SRV-LIN1-01** à l'aide d'OpenLDAP.

Il permet de centraliser la gestion des utilisateurs et l'authentification des différents services de l'infrastructure, notamment Nextcloud.

---

## Installation

```bash
apt install slapd ldap-utils
```

---

## Configuration LDAP

Base DN :

```text
dc=LIN09,dc=local
```

## Structure de l'annuaire

### Unités Organisationnelles (OU)

```text
People

Groups
```

### Groupes

```text
managers

ingenieurs

developpeurs

logiciels
```

### Utilisateurs

```text
man01

man02

ing01

ing02

dev01

dev02
```

---

## Vérification

Affichage du contenu de l'annuaire :

```bash
ldapsearch -x -LLL -b dc=LIN09,dc=local
```

Vérification d'un utilisateur :

```bash
ldapsearch -x -LLL -b dc=LIN09,dc=local "(uid=dev01)"
```

---

## Exemple d'utilisation

Connexion à Nextcloud avec un compte LDAP :

```text
Utilisateur : dev01

Mot de passe : ********
```

Les utilisateurs créés dans LDAP peuvent ainsi s'authentifier sur les différents services compatibles avec l'annuaire.

---

## Dépannage

Vérification du service :

```bash
systemctl status slapd
```

Consultation de l'annuaire :

```bash
ldapsearch -x -LLL -b dc=LIN09,dc=local
```

---

## Conclusion

Le serveur LDAP centralise l'ensemble des comptes utilisateurs de l'infrastructure et facilite l'authentification sur les différents services, notamment Nextcloud.

---

# Maintenance

## Sauvegarde LDAP

```bash
slapcat > ldap-backup.ldif
```

## Sauvegarde DHCP

```bash
cp /etc/kea/kea-dhcp4.conf /root/kea-dhcp4.conf.backup 
```

## Redémarrage des services

```bash
systemctl restart bind9

systemctl restart kea-dhcp4-server

systemctl restart slapd
```

---

# Bonnes pratiques

- Sauvegarder régulièrement LDAP.

- Utiliser des mots de passe robustes.

- Vérifier les logs régulièrement.

- Restreindre l'accès administrateur.

---

# Limites

- Pas de redondance DNS.

- Pas de haute disponibilité LDAP.

- Infrastructure destinée à un environnement pédagogique.

# NAS-LIN1-01

## Présentation

NAS-LIN1-01 héberge les données de l'infrastructure.

Services :

- OpenMediaVault
- RAID1
- NFS

## Configuration matérielle

| Ressource       | Valeur         |
| --------------- | -------------- |
| RAM             | 1 GO           |
| Disques Système | 10 GO          |
| RAID1           | 2 x 10GO       |
| OS              | OpenMediaVault |

## RAID1

### Objectif

Assurer la redondance des données.

### Validation

```bash
cat /proc/mdstat
```

## Partages

```
Commun
Clients
Logiciels
Perso
```

## NFS

### Validation

```bash
exportfs -v
```

```bash
showmount -e localhost
```

## ACL

### Vérification

```bashb
getfacl /export/Commun
```

## Dépannage

```bashb
systemctl status nfs-kernel-server
```

## Maintenance

```bash
df -h
```

```bash
cat /proc/mdstat
```

# SRV-LIN1-02

## Présentation

SRV-LIN1-02 héberge la plateforme Nextcloud.

Fonctions :

- Gestion de fichiers
- Synchronisation
- LDAP
- NFS

## Configuration Matérielle

| Ressource | Valeur      |
| --------- | ----------- |
| RAM       | 2 GO        |
| Disque    | 10 GO       |
| IP        | 10.10.10.22 |

## Installation de Nextcloud

### Services utilisés

- Apache2

- MariaDB

- PHP

- Nextcloud

## Intégration LDAP

### Serveur LDAP

- 10.10.10.11

### Base DN

```
dc=LIN09,dc=local
```

### Validation

Connexion avec :

```
dev01
```

## Montage NFS

### Répertoires

```
/mnt/Commun
/mnt/Clients
/mnt/Logiciels
/mnt/Perso
```

### Validation

```bash
mount | grep nfs
```

## Stockage externes

| Stockage  | Chemin         |
| --------- | -------------- |
| Commun    | /mnt/Commun    |
| Clients   | /mnt/Clients   |
| Logiciels | /mnt/Logiciels |
| Perso     | /mnt/Perso     |

## Dépannage

```bash
tail -f /var/www/nextcloud/data/nextcloud.log
```

```
sudo -u www-data php occ files:scan --all
```

# Validation de l'infrastructure

## Test DNS

```bash
nslookup srv-lin1-01
nslookup srv-lin1-02
nslookup nas-lin1-01
```

## Test DHCP

```bash
ip a
```

## Test LDAP

connexion avec:

```
man01
dev01
ing01
```

## Test Nextcloud

Création: 

```
test.txt
```

Dans:

```
Commun
```

## Test de synchronisation

| Perso | /mnt/Perso |
| ----- | ---------- |

## Dépannage

```bash
tail -f /var/www/nextcloud/data/nextcloud.log
```

```bash
sudo -u www-data php occ files:scan --all
```



---

# 5. Validation de l'infrastructure

## Test DNS

```bash
nslookup srv-lin1-01

nslookup srv-lin1-02

nslookup nas-lin1-01

```



## Test DHCP

```bash
ip a
```

## Test LDAP

Connexion avec :

```
man01

dev01

ing01
```

## Test Nextcloud

Création :

```
test.txt
```

dans :

```
Commun
```

## Test de synchronisation

Création d'un fichier depuis un client.

Vérification de la présence du fichier :

- dans Nextcloud 
- sur le NAS 
- sur les autres clients

# Maintenance

## Sauvegarde LDAP

```
slapcat > ldap-backup.ldif
```

## Sauvegarde DHCP

```bash
cp /etc/kea/kea-dhcp4.conf /root/kea-dhcp4.conf.backup
```

## Vérification RAID

```bash
cat /proc/mdstat
```

## Redémarrage des services

```bash
systemctl restart bind9
systemctl restart kea-dhcp4-server
systemctl restart slapd
```

# Bonnes pratiques

- Sauvegarder régulièrement l'annuaire LDAP.
- Surveiller l'état du RAID.
- Utiliser des mots de passe robustes.
- Vérifier les journaux système.
- Tester régulièrement les sauvegardes.

# Limites

Pas de haute disponibilité.

- Pas de redondance DNS.
- Pas de serveur LDAP secondaire.
- Infrastructure conçue pour un environnement pédagogique.

# Conclusion

L'infrastructure répond aux objectifs du projet. Les services DNS, DHCP, LDAP, NFS et Nextcloud sont opérationnels. Les utilisateurs LDAP peuvent s'authentifier sur Nextcloud et accéder aux ressources de stockage selon les droits définis.