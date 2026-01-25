# Script-d-installation-de-Zabbix-pour-serveur-Linux
Script Bash pour déployer Zabbix 7.0 LTS sur Debian 12. Automatise l'installation complète de la stack : Serveur, Agent, Nginx, PHP et MariaDB (avec création et import du schéma SQL). Configuration clé en main suivant la documentation officielle.

---

# Version Française

## 📈 Script d'Installation Automatisée de Zabbix 7.0 (Debian 12)

Ce script Bash permet de déployer une instance de monitoring **Zabbix 7.0 LTS** complète sur un serveur **Debian 12 (Bookworm)** en quelques minutes. Il suit strictement la documentation officielle pour garantir une installation propre et stable.

### 🛠 Fonctionnalités

Le script automatise l'intégralité de la "pile" technique nécessaire (LEMP stack + Zabbix) :

1. **Préparation** : Ajout du dépôt officiel Zabbix 7.0 et mise à jour du système.
2. **Installation des composants** : Zabbix Server (MySQL), Frontend (PHP), Agent et scripts SQL.
3. **Base de données** : Installation de **MariaDB**, sécurisation (`mysql_secure_installation`), création de la base et de l'utilisateur, et import automatique du schéma initial.
4. **Serveur Web** : Configuration de **Nginx** et **PHP-FPM** pour l'interface web (port 8080 par défaut).
5. **Système** : Configuration des services (activation au démarrage) et ouverture du port via `nftables`.

### 📋 Prérequis

* Un serveur sous **Debian 12**.
* Droits **root** (le script doit être lancé en tant que root ou via sudo).
* *Note : Les variables (mot de passe BDD, port Nginx) sont modifiables en début de script.*

### 🚀 Utilisation

```bash
chmod +x script-d-installation-de-zabbix-pour-debian-12.sh
sudo ./script-d-installation-de-zabbix-pour-debian-12.sh

```

Une fois l'installation terminée, accédez à l'interface via :
`http://votre-ip:8080`

* **User** : Admin
* **Password** : zabbix

---

# English Version

## 📈 Automated Zabbix 7.0 Installation Script (Debian 12)

This Bash script deploys a full **Zabbix 7.0 LTS** monitoring instance on a **Debian 12 (Bookworm)** server in minutes. It strictly follows the official documentation to ensure a clean and stable installation.

### 🛠 Features

The script automates the entire technical stack (LEMP stack + Zabbix):

1. **Preparation**: Adds the official Zabbix 7.0 repository and updates the system.
2. **Component Installation**: Zabbix Server (MySQL), Frontend (PHP), Agent, and SQL scripts.
3. **Database**: Installs **MariaDB**, secures it (`mysql_secure_installation`), creates the database/user, and automatically imports the initial schema.
4. **Web Server**: Configures **Nginx** and **PHP-FPM** for the web interface (default port 8080).
5. **System**: Configures services (enable on boot) and opens the port via `nftables`.

### 📋 Prerequisites

* A server running **Debian 12**.
* **Root** privileges (run as root or via sudo).
* *Note: Variables (DB password, Nginx port) can be customized at the top of the script.*

### 🚀 Usage

```bash
chmod +x script-d-installation-de-zabbix-pour-debian-12.sh
sudo ./script-d-installation-de-zabbix-pour-debian-12.sh

```

Once finished, access the interface via:
`http://your-ip:8080`

* **User**: Admin
* **Password**: zabbix

---

**English Version:**
Bash script to deploy Zabbix 7.0 LTS on Debian 12. Automates the full stack installation: Server, Agent, Nginx, PHP, and MariaDB (including DB creation and schema import). A turnkey solution following the official Zabbix documentation.
