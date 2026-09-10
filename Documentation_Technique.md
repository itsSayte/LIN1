# Documentation Technique - LIN1

## 1. Informations Générales
## Objectifs


### Projet

Mise en place d'une infrastructure Linux comprenant :
- DNS (Bind9)
- DHCP (Kea DHCPv4)
- LDAP (OpenLDAP)
- NextCloud
- OpenMediaVault
### Auteur

- Thibault Le Normand

# 2. Objectifs

L'objectif du projet est de fournir :

- Une résolution de noms interne via DNS.

- Une distribution automatique des paramètres réseau via DHCP.

- Une gestion centralisée des utilisateurs via LDAP.

- Un service Cloud avec NextCloud.

- Un espace de stockage partagé avec OpenMediaVault.
---


## Configuration des machines virtuelles
### SRV-LIN1-01
RAM: 1GO
DISK: 20GO
2 Interface (1NAT, 1HO):
- ens33(NAT)
- ens34(Host-Only)
Debian 13
IP Host-only:10.10.10.11
### SRV-LIN1-02


### NAS-LIN1-01
### CLI-LIN1-0X
RAM: 2GO
DISK: 20GO
- ens33(Host-Only)
Debian 13 avec interface
IP Host-only:DHCP 