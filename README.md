# Script-d-installation-de-Zabbix-pour-serveur-Linux
Scripts Bash pour déployer Zabbix 7.0 LTS sur Debian. Deux versions : un script TUI interactif (Debian 12 & 13, Agent 2, recommandé) et le script historique Debian 12. Stack complète : Serveur, Agent, NGINX, PHP et MariaDB, en suivant la documentation officielle Zabbix.

---

# Version Française

## 📈 Installation Automatisée de Zabbix 7.0 LTS (Debian 12 & 13)

Ce dépôt contient **deux scripts** :

| Script | Systèmes | Agent | Interface |
|---|---|---|---|
| `install-zabbix-tui.sh` ⭐ **recommandé** | Debian 12 (Bookworm) & Debian 13 (Trixie) | Au choix : Agent 2 ou classique | TUI interactive (whiptail) |
| `script-d-installation-de-zabbix-pour-debian-12.sh` | Debian 12 uniquement | Agent classique | Script linéaire historique |

Les deux suivent strictement la [documentation officielle Zabbix](https://www.zabbix.com/download?zabbix=7.0&os_distribution=debian) pour garantir une installation propre et stable : Zabbix Server 7.0 LTS + Frontend (PHP-FPM) + **NGINX** + **MariaDB** (le « MySQL » des dépôts Debian).

### ⭐ Nouveau script TUI : `install-zabbix-tui.sh`

Une interface en mode texte (whiptail) vous guide pas à pas : **l'installation ne commence qu'après votre confirmation finale** (seuls le fichier journal et, si absents, les outils `whiptail`/`wget` sont mis en place avant) :

1. **Détection automatique** : version de Debian (12/13), architecture (amd64/arm64), connectivité vers le dépôt Zabbix.
2. **Choix de l'agent** : **Zabbix Agent 2** (Go, plugins MongoDB/MSSQL/PostgreSQL — présélectionné sur Debian 13) ou agent classique (C), avec explication des différences.
3. **Base de données** : MariaDB installé et **durci automatiquement** (équivalent non interactif de `mysql_secure_installation`), création de la base `zabbix` (utf8mb4/utf8mb4_bin) et import du schéma avec **vérification du nombre de tables**.
4. **Serveur web** : NGINX (port et `server_name` au choix, 8080 par défaut ; gestion du conflit avec le site par défaut si port 80), fuseau horaire PHP.
5. **Robustesse** : arrêt à la première erreur avec indication de l'étape en échec, journal complet dans `/var/log/zabbix-install-tui.log`, sauvegarde `.bak` des fichiers de configuration modifiés, ré-exécution possible (base existante détectée et préservée).
6. **Vérifications finales** : état des services, port en écoute, réponse HTTP réelle du frontend.
7. **Pédagogie** : chaque étape explique *pourquoi* elle est faite, avec des conseils (`[CONSEIL]`) sur la sécurité, le pare-feu (ports 10050/10051) et les premières actions à mener.

### 📋 Prérequis

* Un serveur **Debian 12 (Bookworm)** ou **Debian 13 (Trixie)**, amd64 ou arm64.
* Droits **root** (le script doit être lancé en tant que root ou via sudo).
* Un accès Internet vers `repo.zabbix.com` et les dépôts Debian.

### 🚀 Utilisation

```bash
chmod +x install-zabbix-tui.sh
sudo ./install-zabbix-tui.sh
```

Laissez-vous guider par l'interface. Une fois l'installation terminée, accédez à l'interface via :
`http://votre-ip:8080` (ou le port que vous avez choisi)

* **Utilisateur** : Admin
* **Mot de passe** : zabbix

> ⚠️ **Changez le mot de passe Admin dès la première connexion.**

### 🕰 Script historique (Debian 12)

L'ancien script `script-d-installation-de-zabbix-pour-debian-12.sh` reste disponible et inchangé pour les utilisateurs existants :

```bash
chmod +x script-d-installation-de-zabbix-pour-debian-12.sh
sudo ./script-d-installation-de-zabbix-pour-debian-12.sh
```

*Note : ses variables (mot de passe BDD, port Nginx) se modifient en début de script, et il lance l'assistant interactif `mysql_secure_installation`.*

---

# English Version

## 📈 Automated Zabbix 7.0 LTS Installation (Debian 12 & 13)

This repository contains **two scripts**:

| Script | Systems | Agent | Interface |
|---|---|---|---|
| `install-zabbix-tui.sh` ⭐ **recommended** | Debian 12 (Bookworm) & Debian 13 (Trixie) | Your choice: Agent 2 or classic | Interactive TUI (whiptail) |
| `script-d-installation-de-zabbix-pour-debian-12.sh` | Debian 12 only | Classic agent | Legacy linear script |

Both strictly follow the [official Zabbix documentation](https://www.zabbix.com/download?zabbix=7.0&os_distribution=debian) to ensure a clean and stable installation: Zabbix Server 7.0 LTS + Frontend (PHP-FPM) + **NGINX** + **MariaDB** (Debian's "MySQL").

### ⭐ New TUI script: `install-zabbix-tui.sh`

A text-mode interface (whiptail) guides you step by step: **the installation only starts after your final confirmation** (only the log file and, if missing, the `whiptail`/`wget` tools are set up beforehand):

1. **Auto-detection**: Debian version (12/13), architecture (amd64/arm64), connectivity to the Zabbix repository.
2. **Agent choice**: **Zabbix Agent 2** (Go, MongoDB/MSSQL/PostgreSQL plugins — preselected on Debian 13) or the classic C agent, with an explanation of the differences.
3. **Database**: MariaDB installed and **hardened automatically** (non-interactive equivalent of `mysql_secure_installation`), `zabbix` database created (utf8mb4/utf8mb4_bin) and schema imported with a **table-count verification**.
4. **Web server**: NGINX (port and `server_name` of your choice, 8080 by default; default-site conflict handled when using port 80), PHP timezone.
5. **Robustness**: stops at the first error and names the failing step, full log in `/var/log/zabbix-install-tui.log`, `.bak` backups of modified config files, safe re-runs (existing database detected and preserved).
6. **Final checks**: service states, listening port, real HTTP response from the frontend.
7. **Educational**: every step explains *why* it is performed, with `[CONSEIL]` (tip) messages about security, firewalling (ports 10050/10051) and first post-install actions.

### 📋 Prerequisites

* A server running **Debian 12 (Bookworm)** or **Debian 13 (Trixie)**, amd64 or arm64.
* **Root** privileges (run as root or via sudo).
* Internet access to `repo.zabbix.com` and the Debian repositories.

### 🚀 Usage

```bash
chmod +x install-zabbix-tui.sh
sudo ./install-zabbix-tui.sh
```

Follow the interface. Once finished, access the web UI via:
`http://your-ip:8080` (or the port you chose)

* **User**: Admin
* **Password**: zabbix

> ⚠️ **Change the Admin password right after your first login.**

### 🕰 Legacy script (Debian 12)

The original `script-d-installation-de-zabbix-pour-debian-12.sh` remains available, unchanged, for existing users:

```bash
chmod +x script-d-installation-de-zabbix-pour-debian-12.sh
sudo ./script-d-installation-de-zabbix-pour-debian-12.sh
```

*Note: its variables (DB password, Nginx port) are set at the top of the script, and it runs the interactive `mysql_secure_installation` wizard.*
