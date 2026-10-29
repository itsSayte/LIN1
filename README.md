# LIN1 - Déploiement automatisé de l'infrastructure

## Auteur

**Thibault Le Normand**

---

# Présentation

Ce projet permet le déploiement automatique d'une infrastructure Linux composée de plusieurs services réseau.

Les scripts fournis réalisent l'installation et la configuration automatique des serveurs nécessaires au fonctionnement de l'environnement.

---

# Infrastructure

## Serveurs

| Machine | Adresse IP | Fonction |
|----------|------------|----------|
| SRV-LIN1-01 | 10.10.10.11 | DNS, DHCP, LDAP, LAM, NAT |
| SRV-LIN1-02 | 10.10.10.22 | Nextcloud |
| NAS-LIN1-01 | 10.10.10.33 | OpenMediaVault, RAID1, NFS |

---

# Arborescence

```text
.
├── README.md
├── SRV-LIN1-01.sh
├── SRV-LIN1-02.sh
├── LDAP_ldif
│   ├── base.ldif
│   ├── groups.ldif
│   └── users.ldif
└── Documentation
    ├── Documentation-Technique.md
    └── POC.md
```

---

# Prérequis

## Système d'exploitation

Les scripts ont été développés et testés sur :

```text
Debian 13
```

## Permissions

Les scripts doivent être exécutés avec les privilèges administrateur :

```bash
sudo -i
```

ou :

```bash
su -
```

## Fichiers LDAP

Le répertoire :

```text
LDAP_ldif
```

doit être présent dans le même dossier que :

```text
SRV-LIN1-01.sh
```

## Configuration DNS
Pour évité tout problème lors du déploiement sur les deux serveurs. 
```bash
cat > /etc/resolv.conf << EOF
search LIN09.local
nameserver ${DNS_SERVER}
EOF
```
---

# Utilisation

## Déploiement de SRV-LIN1-01

### Fonction

Le script configure automatiquement :

- le réseau ;
- le routage IPv4 ;
- le NAT ;
- le serveur DNS Bind9 ;
- le serveur DHCP Kea ;
- le serveur LDAP OpenLDAP ;
- LDAP Account Manager (LAM).

### Lancement

```bash
chmod +x SRV-LIN1-01.sh

./SRV-LIN1-01.sh
```

### Vérifications

Contrôle des services :

```bash
systemctl is-active named
systemctl is-active kea-dhcp4-server
systemctl is-active slapd
systemctl is-active apache2
```

Toutes les commandes doivent retourner :

```text
active
```

### Vérification DNS

```bash
nslookup srv-lin1-02.LIN09.local
```

### Vérification LDAP

```bash
ldapsearch -x -LLL \
-b dc=LIN09,dc=local
```

### Accès LAM

```text
http://10.10.10.11/lam
```

---

## Déploiement de SRV-LIN1-02

### Fonction

Le script configure automatiquement :

- SSH ;
- Apache ;
- PHP ;
- MariaDB ;
- Nextcloud ;
- les montages NFS ;
- les outils LDAP.

### Lancement

```bash
chmod +x SRV-LIN1-02.sh

./SRV-LIN1-02.sh
```

### Vérifications

Apache :

```bash
systemctl status apache2
```

MariaDB :

```bash
systemctl status mariadb
```

NFS :

```bash
mount | grep nfs
```

### Accès Nextcloud

```text
https://10.10.10.22
```

---

# Configuration manuelle après installation

## Nextcloud

Après l'exécution du script SRV-LIN1-02 :

1. Ouvrir :

```text
https://10.10.10.22
```

2. Créer le compte administrateur.

3. Configurer la base de données :

```text
Base de données : nextcloud
Utilisateur : nextcloud
Mot de passe : Pa$$w0rd
Serveur : localhost
```

---

## LDAP dans Nextcloud

Configurer :

```text
Serveur LDAP : 10.10.10.11

Base DN :
dc=LIN09,dc=local

Compte LDAP :
cn=admin,dc=LIN09,dc=local
```

---

## Stockages externes

Configurer les partages :

```text
/mnt/Commun
/mnt/Clients
/mnt/Logiciels
/mnt/Perso
```

dans :

```text
Administration
→ Stockages externes
```

---

# Utilisateurs LDAP

## Groupes

```text
managers
ingenieurs
developpeurs
logiciels
```

## Utilisateurs

```text
man01
man02

ing01
ing02

dev01
dev02
```

---

# Tests recommandés

## DNS

```bash
nslookup google.com

nslookup srv-lin1-02.LIN09.local
```

## DHCP

```bash
ip a
```

## LDAP

```bash
ldapwhoami -x \
-D "cn=admin,dc=LIN09,dc=local"
```

## NFS

```bash
showmount -e 10.10.10.33
```

## Nextcloud

Connexion :

```text
dev01
man01
ing01
dev02
```

---

# Dépannage

## DNS

```bash
systemctl restart named
```

## DHCP

```bash
systemctl restart kea-dhcp4-server
```

## LDAP

```bash
systemctl restart slapd
```

## Apache

```bash
systemctl restart apache2
```

## Vérification générale

```bash
systemctl --failed
```

---
