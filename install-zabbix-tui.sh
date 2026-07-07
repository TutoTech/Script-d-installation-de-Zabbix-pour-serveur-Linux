#!/bin/bash
#===============================================================================
#
#  INSTALLATION AUTOMATISÉE DE ZABBIX 7.0 LTS — VERSION TUI (whiptail)
#
#  Systèmes supportés : Debian 12 (Bookworm) et Debian 13 (Trixie)
#  Pile installée     : Zabbix Server 7.0 LTS + Frontend (PHP-FPM)
#                       + Agent Zabbix (classique OU Agent 2, au choix)
#                       + MariaDB (le « MySQL » officiel des dépôts Debian)
#                       + NGINX comme serveur web
#
#  Ce script suit STRICTEMENT la procédure officielle Zabbix :
#    https://www.zabbix.com/download?zabbix=7.0&os_distribution=debian
#    https://www.zabbix.com/documentation/7.0/en/manual/installation/install_from_packages/debian_ubuntu
#
#  ─── POURQUOI CES CHOIX TECHNIQUES ? ───────────────────────────────────────
#  • MariaDB plutôt qu'Oracle MySQL : c'est le moteur « MySQL » fourni par
#    Debian. La version 11.8 de Debian 13 est dans la plage officiellement
#    supportée par Zabbix 7.0 (MariaDB 10.5 → 12.3). Aucun dépôt externe requis.
#  • Agent 2 : réécriture moderne en Go de l'agent, avec système de plugins
#    (MongoDB, MSSQL, PostgreSQL, Docker...). C'est l'agent recommandé pour les
#    nouvelles installations ; l'agent classique (en C) reste disponible.
#  • whiptail : outil de dialogues en mode texte présent de base sur Debian.
#
#  ─── PRÉREQUIS ─────────────────────────────────────────────────────────────
#  • Être root (sudo ./install-zabbix-tui.sh)
#  • Un accès Internet vers repo.zabbix.com et les dépôts Debian
#  • Un serveur « propre » de préférence (pas d'autre service sur le port web)
#
#  ─── JOURNAL ───────────────────────────────────────────────────────────────
#  Tout ce que fait le script est journalisé dans :
#    /var/log/zabbix-install-tui.log
#  En cas d'échec, consultez ce fichier : il contient la sortie complète des
#  commandes (apt, mariadb, nginx...) et l'étape précise qui a échoué.
#
#===============================================================================

# « Mode strict » bash : le script s'arrête à la première erreur (-e), une
# variable non définie est une erreur (-u), et une erreur au milieu d'un
# pipeline n'est pas masquée (pipefail). -E propage le trap ERR aux fonctions.
set -Eeuo pipefail

#===============================================================================
# CONSTANTES ET VARIABLES GLOBALES
#===============================================================================

readonly LOG_FILE="/var/log/zabbix-install-tui.log"
readonly ZABBIX_VERSION="7.0"
# Le paquet « zabbix-release » configure le dépôt APT officiel de Zabbix.
# L'URL exacte dépend de la version de Debian et de l'architecture ;
# elle est construite dans install_zabbix_repo() après détection du système.
readonly ZABBIX_REPO_BASE="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}"

# Valeurs choisies via la TUI (remplies par les fonctions tui_*)
DEBIAN_VERSION=""        # 12 ou 13
AGENT_PACKAGE=""         # zabbix-agent ou zabbix-agent2
AGENT_SERVICE=""         # nom du service systemd correspondant
DB_PASSWORD=""           # mot de passe de l'utilisateur MariaDB « zabbix »
SERVER_NAME=""           # server_name pour NGINX
LISTEN_PORT=""           # port d'écoute NGINX du frontend
PHP_TIMEZONE=""          # fuseau horaire PHP (obligatoire pour le frontend)
SKIP_DB_IMPORT="non"     # passe à « oui » si une base zabbix existe déjà

# Renseignée au fil de l'eau pour que le message d'erreur indique où ça a cassé.
CURRENT_STEP="initialisation"

# Fichier d'identifiants MariaDB temporaire (créé plus tard, supprimé à la fin).
MYSQL_CNF=""

#===============================================================================
# AFFICHAGE ET JOURNALISATION
#===============================================================================

readonly C_INFO="\033[1;34m"     # bleu
readonly C_OK="\033[1;32m"       # vert
readonly C_WARN="\033[1;33m"     # jaune
readonly C_ERR="\033[1;31m"      # rouge
readonly C_TIP="\033[1;36m"      # cyan
readonly C_RESET="\033[0m"

# Chaque message est affiché à l'écran ET ajouté au journal.
log()     { echo -e "${C_INFO}[INFO]${C_RESET}    $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${C_OK}[SUCCÈS]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${C_WARN}[ATTENTION]${C_RESET} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${C_ERR}[ERREUR]${C_RESET}  $*" | tee -a "$LOG_FILE" >&2; }
tip()     { echo -e "${C_TIP}[CONSEIL]${C_RESET} $*" | tee -a "$LOG_FILE"; }

# Exécute une commande en envoyant sa sortie complète dans le journal.
# À l'écran, on ne garde que nos messages : le détail reste consultable
# dans /var/log/zabbix-install-tui.log (pédagogie sans pollution visuelle).
run_logged() {
    echo ">>> $*" >>"$LOG_FILE"
    "$@" >>"$LOG_FILE" 2>&1
}

#===============================================================================
# GESTION D'ERREURS ET NETTOYAGE
#===============================================================================

# En cas d'erreur non gérée, on explique à l'utilisateur OÙ le script a échoué
# et COMMENT diagnostiquer, au lieu de mourir en silence.
on_error() {
    local exit_code=$?
    error "Le script a échoué à l'étape : ${CURRENT_STEP} (code ${exit_code})."
    error "Consultez le journal détaillé : ${LOG_FILE}"
    tip   "Le script peut être relancé après correction : les étapes déjà"
    tip   "réalisées (dépôt, paquets, base de données) sont détectées et gérées."
    cleanup
    exit "$exit_code"
}

# Supprime le fichier d'identifiants MariaDB temporaire : il contient le mot de
# passe de la base et ne doit jamais rester sur le disque après l'installation.
cleanup() {
    if [[ -n "$MYSQL_CNF" && -f "$MYSQL_CNF" ]]; then
        rm -f "$MYSQL_CNF"
    fi
}

trap on_error ERR
trap cleanup EXIT

# Sortie propre quand l'utilisateur annule dans un écran whiptail.
abort_by_user() {
    trap - ERR
    echo ""
    warn "Installation annulée par l'utilisateur : le script s'arrête ici."
    warn "Les étapes déjà réalisées (le cas échéant) restent en place ;"
    warn "le détail de ce qui a été fait se trouve dans : ${LOG_FILE}"
    cleanup
    exit 1
}

#===============================================================================
# OUTILS
#===============================================================================

# Sur Debian 13, MariaDB 11.8 fournit la commande « mariadb » et les anciens
# alias « mysql » peuvent être absents (paquet de compatibilité séparé).
# On détecte donc le bon binaire une fois pour toutes.
MYSQL_CMD=""
detect_mysql_cmd() {
    if command -v mariadb >/dev/null 2>&1; then
        MYSQL_CMD="mariadb"
    elif command -v mysql >/dev/null 2>&1; then
        MYSQL_CMD="mysql"
    else
        error "Ni « mariadb » ni « mysql » n'est disponible. MariaDB est-il installé ?"
        return 1
    fi
}

# Requête SQL en tant que root MariaDB.
# Les installations Debian récentes authentifient root via « unix_socket » :
# être root sur le système suffit, aucun mot de passe n'est demandé.
mysql_root() {
    "$MYSQL_CMD" --batch --skip-column-names -uroot "$@"
}

# Requête SQL en tant qu'utilisateur « zabbix », via un fichier d'identifiants
# temporaire (chmod 600). On évite ainsi de passer le mot de passe sur la ligne
# de commande, où il serait visible de tous dans la liste des processus (ps).
mysql_zabbix() {
    "$MYSQL_CMD" --defaults-extra-file="$MYSQL_CNF" "$@"
}

# Échappe une chaîne pour l'utiliser dans une chaîne SQL entre quotes simples.
sql_escape() {
    local s="$1"
    s="${s//\\/\\\\}"   # les antislash d'abord
    s="${s//\'/\\\'}"   # puis les quotes simples
    printf '%s' "$s"
}

# Échappe une chaîne pour l'utiliser comme REMPLACEMENT dans sed (délimiteur |).
sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

#===============================================================================
# ÉCRANS TUI (whiptail)
# whiptail écrit le choix de l'utilisateur sur la sortie d'erreur ; l'astuce
# « 3>&1 1>&2 2>&3 » permet de récupérer ce choix dans une variable bash.
# Un code retour non nul signifie « Annuler » ou « Échap » → on quitte proprement.
#===============================================================================

readonly TUI_BACKTITLE="Installation de Zabbix 7.0 LTS (Debian 12 / 13) — MariaDB + NGINX"

tui_msgbox() {
    whiptail --backtitle "$TUI_BACKTITLE" --title "$1" --msgbox "$2" 20 76
}

tui_yesno() {
    whiptail --backtitle "$TUI_BACKTITLE" --title "$1" --yesno "$2" 20 76
}

# NOTE : ces deux fonctions sont appelées via une substitution de commande
# « var=$(tui_input ...) », donc dans un sous-shell : elles ne peuvent pas
# arrêter le script elles-mêmes. Elles renvoient le code retour de whiptail
# et c'est l'APPELANT qui gère l'annulation avec « || abort_by_user ».
tui_input() {
    local title="$1" text="$2" default="$3" result
    if ! result=$(whiptail --backtitle "$TUI_BACKTITLE" --title "$title" \
        --inputbox "$text" 20 76 "$default" 3>&1 1>&2 2>&3); then
        return 1
    fi
    printf '%s' "$result"
}

tui_password() {
    local title="$1" text="$2" result
    if ! result=$(whiptail --backtitle "$TUI_BACKTITLE" --title "$title" \
        --passwordbox "$text" 20 76 3>&1 1>&2 2>&3); then
        return 1
    fi
    printf '%s' "$result"
}

#===============================================================================
# ÉTAPE 0 — CONTRÔLES PRÉALABLES (avant toute modification du système)
#===============================================================================

preflight_checks() {
    CURRENT_STEP="contrôles préalables"

    # ── Droits root ──────────────────────────────────────────────────────────
    # L'installation touche APT, systemd, /etc : impossible sans être root.
    if [[ $EUID -ne 0 ]]; then
        error "Ce script doit être lancé en root : sudo $0"
        exit 1
    fi

    touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
    log "Journal d'installation : ${LOG_FILE}"

    # ── Outils indispensables au script lui-même ─────────────────────────────
    # whiptail (dialogues) et wget (téléchargements) sont normalement présents
    # de base sur Debian, mais peuvent manquer sur une installation minimale :
    # on les installe ici plutôt que d'échouer plus loin avec un message
    # cryptique « command not found ». C'est la SEULE modification du système
    # faite avant l'écran de confirmation (avec la création du journal).
    local missing_tools=()
    command -v whiptail >/dev/null 2>&1 || missing_tools+=(whiptail)
    command -v wget     >/dev/null 2>&1 || missing_tools+=(wget)
    if (( ${#missing_tools[@]} > 0 )); then
        log "Installation des outils requis par le script : ${missing_tools[*]}..."
        run_logged apt-get update
        run_logged apt-get install -y "${missing_tools[@]}"
    fi

    # ── Détection de la version de Debian ────────────────────────────────────
    # /etc/os-release est le standard systemd pour identifier la distribution.
    local os_id="" os_version=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        os_id="${ID:-}"
        os_version="${VERSION_ID:-}"
    fi

    if [[ "$os_id" != "debian" ]]; then
        error "Système détecté : « ${os_id:-inconnu} ». Ce script ne supporte que Debian 12 et 13."
        tip   "Pour Ubuntu ou une autre distribution, suivez la procédure officielle :"
        tip   "https://www.zabbix.com/download"
        exit 1
    fi

    case "$os_version" in
        12|13)
            DEBIAN_VERSION="$os_version"
            log "Debian ${DEBIAN_VERSION} détecté ($( [[ $DEBIAN_VERSION == 12 ]] && echo Bookworm || echo Trixie ))."
            ;;
        *)
            # Cas des systèmes testing/sid sans VERSION_ID : on laisse le choix,
            # mais on prévient que ce n'est pas un environnement supporté.
            warn "Version de Debian non identifiée formellement (VERSION_ID='${os_version}')."
            DEBIAN_VERSION=$(whiptail --backtitle "$TUI_BACKTITLE" --title "Version de Debian" \
                --menu "La version de Debian n'a pas pu être détectée automatiquement.\n\nQuelle version cible utiliser pour le dépôt Zabbix ?\n(Seuls Debian 12 et 13 stables sont supportés officiellement.)" 18 76 2 \
                "12" "Debian 12 (Bookworm)" \
                "13" "Debian 13 (Trixie)" 3>&1 1>&2 2>&3) || abort_by_user
            ;;
    esac

    # ── Architecture ─────────────────────────────────────────────────────────
    # Zabbix publie un dépôt distinct pour ARM64 (Raspberry Pi 64 bits, etc.).
    ARCH=$(dpkg --print-architecture)
    case "$ARCH" in
        amd64)  REPO_OS_PATH="debian" ;;
        arm64)  REPO_OS_PATH="debian-arm64" ;;
        *)
            error "Architecture « ${ARCH} » non gérée par ce script (amd64 et arm64 uniquement)."
            exit 1
            ;;
    esac
    log "Architecture : ${ARCH}"

    # ── Connectivité vers le dépôt Zabbix ────────────────────────────────────
    # Mieux vaut échouer tout de suite avec un message clair qu'au milieu
    # de l'installation avec un wget cryptique.
    log "Vérification de l'accès à repo.zabbix.com..."
    if ! wget -q --spider --timeout=15 "https://repo.zabbix.com/"; then
        error "Impossible de joindre https://repo.zabbix.com/."
        tip   "Vérifiez la connexion Internet, le DNS et un éventuel proxy (variable https_proxy)."
        exit 1
    fi
    success "Contrôles préalables terminés."
}

#===============================================================================
# ÉTAPE 1 — DIALOGUE AVEC L'UTILISATEUR (aucune modification système ici)
#===============================================================================

tui_collect_settings() {
    CURRENT_STEP="configuration via l'interface TUI"

    # ── Écran de bienvenue ───────────────────────────────────────────────────
    tui_msgbox "Bienvenue" \
"Ce script va installer une pile de supervision Zabbix ${ZABBIX_VERSION} LTS complète sur ce serveur Debian ${DEBIAN_VERSION} :

  • Zabbix Server (moteur de supervision)
  • Interface web Zabbix (PHP-FPM derrière NGINX)
  • MariaDB (base de données MySQL des dépôts Debian)
  • Un agent Zabbix pour superviser ce serveur lui-même

La procédure suit la documentation officielle Zabbix.

L'INSTALLATION ne commencera qu'après l'écran de récapitulatif
final : vous pourrez annuler à tout moment avec < Annuler > ou
Échap. (Seuls le journal ${LOG_FILE}
et, si nécessaire, les outils whiptail/wget existent déjà.)"

    # ── Choix de l'agent ─────────────────────────────────────────────────────
    # Pédagogie : Agent 2 est le choix moderne ; le classique reste utile si
    # l'on veut un binaire C très léger ou une compatibilité historique.
    local default_agent2="ON" default_agent1="OFF"
    if [[ "$DEBIAN_VERSION" == "12" ]]; then
        # Sur Debian 12 on préserve le comportement historique du dépôt
        # (agent classique), mais Agent 2 reste sélectionnable.
        default_agent2="OFF"; default_agent1="ON"
    fi
    AGENT_PACKAGE=$(whiptail --backtitle "$TUI_BACKTITLE" --title "Choix de l'agent Zabbix" \
        --radiolist \
"Quel agent installer sur CE serveur (pour qu'il se supervise lui-même) ?

Zabbix Agent 2 : réécriture moderne en Go, recommandée pour les
nouvelles installations. Il gère des plugins (MongoDB, MSSQL,
PostgreSQL...) et des contrôles persistants plus efficaces.

Agent classique : binaire C historique, très léger, toujours
maintenu. Choix par défaut des anciennes installations.

(Espace pour sélectionner, Entrée pour valider.)" 22 76 2 \
        "zabbix-agent2" "Agent 2 (Go, plugins) — recommandé" "$default_agent2" \
        "zabbix-agent"  "Agent classique (C)" "$default_agent1" \
        3>&1 1>&2 2>&3) || abort_by_user
    AGENT_SERVICE="$AGENT_PACKAGE"   # le service systemd porte le même nom

    # ── Mot de passe de la base de données ───────────────────────────────────
    # C'est le mot de passe de l'utilisateur MariaDB « zabbix » utilisé par le
    # serveur Zabbix et le frontend. Il ne s'agit PAS du compte web « Admin ».
    local pass1 pass2
    while true; do
        pass1=$(tui_password "Base de données — mot de passe" \
"Choisissez le mot de passe de l'utilisateur MariaDB « zabbix ».

CONSEILS :
  • 12 caractères minimum recommandés (8 exigés ici)
  • mélangez lettres, chiffres et symboles
  • ce mot de passe sera stocké dans /etc/zabbix/zabbix_server.conf
    (fichier lisible uniquement par root et le groupe zabbix)

Il sera demandé une seconde fois pour confirmation.") || abort_by_user
        if [[ ${#pass1} -lt 8 ]]; then
            tui_msgbox "Mot de passe trop court" "Le mot de passe doit contenir au moins 8 caractères.\n\nMerci de recommencer."
            continue
        fi
        pass2=$(tui_password "Base de données — confirmation" "Saisissez à nouveau le même mot de passe :") || abort_by_user
        if [[ "$pass1" == "$pass2" ]]; then
            DB_PASSWORD="$pass1"
            break
        fi
        tui_msgbox "Les mots de passe diffèrent" "Les deux saisies ne correspondent pas.\n\nMerci de recommencer."
    done

    # ── NGINX : nom de serveur et port ───────────────────────────────────────
    local default_name
    default_name=$(hostname -f 2>/dev/null || hostname)
    SERVER_NAME=$(tui_input "NGINX — nom du serveur" \
"Nom de domaine (server_name) utilisé par NGINX pour l'interface web.

Si vous n'avez pas de DNS, laissez la valeur proposée : l'interface
restera de toute façon accessible via l'adresse IP du serveur." \
        "$default_name") || abort_by_user
    [[ -n "$SERVER_NAME" ]] || SERVER_NAME="$default_name"

    while true; do
        LISTEN_PORT=$(tui_input "NGINX — port d'écoute" \
"Port TCP sur lequel l'interface web Zabbix sera servie.

  • 8080 : valeur par défaut de la configuration officielle Zabbix,
    évite tout conflit avec un autre site déjà en place.
  • 80   : port web standard (http://ip/ sans préciser de port).
    Le site NGINX par défaut sera alors désactivé pour libérer le port." \
            "8080") || abort_by_user
        if [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] && (( LISTEN_PORT >= 1 && LISTEN_PORT <= 65535 )); then
            break
        fi
        tui_msgbox "Port invalide" "« ${LISTEN_PORT} » n'est pas un port TCP valide (1-65535).\n\nMerci de recommencer."
    done

    # ── Fuseau horaire PHP ───────────────────────────────────────────────────
    # La documentation officielle recommande de définir date.timezone pour le
    # frontend : sinon les graphiques et horodatages utilisent UTC.
    local default_tz
    default_tz=$(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value 2>/dev/null || echo "Europe/Paris")
    PHP_TIMEZONE=$(tui_input "PHP — fuseau horaire" \
"Fuseau horaire utilisé par l'interface web (horodatage des graphiques,
des événements...).

Format : Région/Ville, par exemple Europe/Paris.
Liste complète : https://www.php.net/manual/fr/timezones.php" \
        "$default_tz") || abort_by_user
    [[ -n "$PHP_TIMEZONE" ]] || PHP_TIMEZONE="Europe/Paris"

    # ── Récapitulatif : dernier arrêt avant modification du système ──────────
    if ! tui_yesno "Récapitulatif — confirmer l'installation ?" \
"Le script va maintenant installer et configurer :

  Système           : Debian ${DEBIAN_VERSION} (${ARCH})
  Zabbix            : ${ZABBIX_VERSION} LTS (dépôt officiel)
  Agent             : ${AGENT_PACKAGE}
  Base de données   : MariaDB — base « zabbix », utilisateur « zabbix »
  Serveur web       : NGINX sur le port ${LISTEN_PORT}
  server_name       : ${SERVER_NAME}
  Fuseau horaire    : ${PHP_TIMEZONE}

C'est le point de non-retour : après confirmation, le script
commence à modifier le système.

Lancer l'installation ?"; then
        abort_by_user
    fi
}

#===============================================================================
# ÉTAPE 2 — DÉPÔT OFFICIEL ZABBIX
#===============================================================================

install_zabbix_repo() {
    CURRENT_STEP="installation du dépôt Zabbix"

    # Le paquet zabbix-release ajoute le dépôt APT officiel + sa clé GPG.
    # « latest_7.0 » pointe toujours vers la dernière révision du paquet
    # de dépôt pour la branche 7.0 : on bénéficie des mises à jour LTS.
    local deb_url="${ZABBIX_REPO_BASE}/${REPO_OS_PATH}/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_VERSION}+debian${DEBIAN_VERSION}_all.deb"
    local deb_file="/tmp/zabbix-release_${ZABBIX_VERSION}+debian${DEBIAN_VERSION}.deb"

    if dpkg -s zabbix-release >/dev/null 2>&1; then
        log "Le paquet zabbix-release est déjà installé — on le met à jour avec la dernière révision."
    fi

    log "Téléchargement du dépôt officiel Zabbix : ${deb_url}"
    run_logged wget -O "$deb_file" "$deb_url"

    log "Installation du paquet de dépôt..."
    run_logged dpkg -i "$deb_file"
    rm -f "$deb_file"

    log "Mise à jour de la liste des paquets (apt update)..."
    run_logged apt-get update
    success "Dépôt Zabbix ${ZABBIX_VERSION} configuré."
}

#===============================================================================
# ÉTAPE 3 — PAQUETS ZABBIX + MARIADB
#===============================================================================

install_packages() {
    CURRENT_STEP="installation des paquets Zabbix et MariaDB"

    log "Installation des paquets (cette étape peut prendre plusieurs minutes) :"
    log "  • zabbix-server-mysql : le serveur de supervision (variante MySQL/MariaDB)"
    log "  • zabbix-frontend-php : l'interface web en PHP"
    log "  • zabbix-nginx-conf   : la configuration NGINX + PHP-FPM prête à l'emploi"
    log "  • zabbix-sql-scripts  : le schéma initial de la base de données"
    log "  • ${AGENT_PACKAGE}    : l'agent qui supervisera ce serveur"
    log "  • mariadb-server      : le serveur de base de données"
    DEBIAN_FRONTEND=noninteractive run_logged apt-get install -y \
        zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf \
        zabbix-sql-scripts "$AGENT_PACKAGE" mariadb-server

    if [[ "$AGENT_PACKAGE" == "zabbix-agent2" ]]; then
        tip "Des plugins Agent 2 existent pour superviser des bases externes :"
        tip "  apt install zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql"
    fi

    # MariaDB doit tourner pour la suite (création de la base).
    run_logged systemctl enable --now mariadb
    detect_mysql_cmd
    success "Paquets installés (client base de données : ${MYSQL_CMD})."
}

#===============================================================================
# ÉTAPE 4 — SÉCURISATION DE MARIADB
#===============================================================================

secure_mariadb() {
    CURRENT_STEP="sécurisation de MariaDB"

    # Équivalent non interactif de « mysql_secure_installation ».
    # Sur Debian, le compte root MariaDB utilise l'authentification
    # « unix_socket » : seul l'utilisateur root du système peut s'y connecter,
    # sans mot de passe — c'est sûr ET pratique pour l'administration.
    log "Durcissement de MariaDB (équivalent de mysql_secure_installation) :"
    log "  • suppression des comptes anonymes"
    log "  • interdiction de la connexion root à distance"
    log "  • suppression de la base de démonstration « test »"
    mysql_root <<'SQL' >>"$LOG_FILE" 2>&1
DELETE FROM mysql.global_priv WHERE User='';
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
SQL
    success "MariaDB sécurisé."
    tip "Le compte root MariaDB reste accessible sans mot de passe, mais UNIQUEMENT"
    tip "pour l'utilisateur root du système (authentification unix_socket)."
}

#===============================================================================
# ÉTAPE 5 — BASE DE DONNÉES ZABBIX (création + import du schéma)
#===============================================================================

create_database() {
    CURRENT_STEP="création de la base de données Zabbix"

    # Idempotence : si une base « zabbix » existe déjà (ré-exécution du script,
    # ancienne installation...), on ne la touche PAS : écraser une base de
    # supervision existante détruirait tout l'historique de métriques.
    local existing
    existing=$(mysql_root -e "SHOW DATABASES LIKE 'zabbix';")
    if [[ -n "$existing" ]]; then
        warn "Une base de données « zabbix » existe déjà sur ce serveur."
        if tui_yesno "Base de données existante" \
"Une base « zabbix » existe déjà.

  • CONSERVER : la base actuelle est gardée telle quelle (aucun
    import de schéma). Le mot de passe de l'utilisateur « zabbix »
    sera tout de même mis à jour avec celui que vous avez saisi.
    → choix adapté à une ré-exécution du script.

  • ANNULER : le script s'arrête sans rien toucher.
    → choix prudent si vous ne savez pas d'où vient cette base.

Conserver la base existante et poursuivre ?"; then
            SKIP_DB_IMPORT="oui"
        else
            abort_by_user
        fi
    fi

    # Le mot de passe est échappé avant injection dans la requête SQL :
    # il peut contenir quotes et antislash sans casser la commande.
    local pw_sql
    pw_sql=$(sql_escape "$DB_PASSWORD")

    log "Création de la base « zabbix » (utf8mb4/utf8mb4_bin, exigé par Zabbix) et de son utilisateur..."
    mysql_root <<SQL >>"$LOG_FILE" 2>&1
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS zabbix@localhost IDENTIFIED BY '${pw_sql}';
ALTER USER zabbix@localhost IDENTIFIED BY '${pw_sql}';
GRANT ALL PRIVILEGES ON zabbix.* TO zabbix@localhost;
FLUSH PRIVILEGES;
SQL

    # Fichier d'identifiants temporaire pour les connexions « zabbix » :
    # jamais de mot de passe en argument de commande (visible dans ps/top).
    MYSQL_CNF=$(mktemp /tmp/zabbix-db-XXXXXX.cnf)
    chmod 600 "$MYSQL_CNF"
    {
        echo "[client]"
        echo "user=zabbix"
        # Les guillemets et antislash éventuels du mot de passe sont doublés
        # pour respecter la syntaxe des fichiers d'options MariaDB.
        printf 'password="%s"\n' "$(printf '%s' "$DB_PASSWORD" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    } >"$MYSQL_CNF"

    success "Base de données et utilisateur prêts."
}

import_schema() {
    CURRENT_STEP="import du schéma de la base Zabbix"

    if [[ "$SKIP_DB_IMPORT" == "oui" ]]; then
        log "Base existante conservée : import du schéma ignoré."
        return 0
    fi

    # log_bin_trust_function_creators : le schéma Zabbix crée des fonctions
    # stockées ; si la journalisation binaire est active, MariaDB exige ce
    # réglage temporaire pour autoriser leur création (procédure officielle).
    # On mémorise la valeur ACTUELLE pour la restaurer à l'identique après
    # l'import — y compris si l'import échoue, afin de ne jamais laisser le
    # serveur avec ce réglage de sécurité assoupli.
    local previous_trust import_ok="oui"
    previous_trust=$(mysql_root -e "SELECT @@GLOBAL.log_bin_trust_function_creators;")
    log "Activation temporaire de log_bin_trust_function_creators (valeur actuelle : ${previous_trust})..."
    mysql_root -e "SET GLOBAL log_bin_trust_function_creators = 1;" >>"$LOG_FILE" 2>&1

    log "Import du schéma initial Zabbix (~170 tables)."
    log "PATIENCE : cette étape peut durer plusieurs minutes, c'est normal."
    if ! zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
        mysql_zabbix --default-character-set=utf8mb4 zabbix >>"$LOG_FILE" 2>&1; then
        import_ok="non"
    fi

    log "Restauration de log_bin_trust_function_creators à sa valeur d'origine (${previous_trust})..."
    mysql_root -e "SET GLOBAL log_bin_trust_function_creators = ${previous_trust};" >>"$LOG_FILE" 2>&1

    if [[ "$import_ok" == "non" ]]; then
        error "L'import du schéma a échoué. Détails dans ${LOG_FILE}."
        exit 1
    fi

    # Vérification : l'import a-t-il vraiment créé les tables ?
    # (Un import silencieusement tronqué est un grand classique de dépannage.)
    local table_count
    table_count=$(mysql_root -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix';")
    if (( table_count < 100 )); then
        error "L'import du schéma semble incomplet : ${table_count} tables trouvées (plus de 100 attendues)."
        exit 1
    fi
    success "Schéma importé et vérifié : ${table_count} tables dans la base « zabbix »."
}

#===============================================================================
# ÉTAPE 6 — CONFIGURATION DU SERVEUR ZABBIX
#===============================================================================

configure_zabbix_server() {
    CURRENT_STEP="configuration du serveur Zabbix"

    local conf="/etc/zabbix/zabbix_server.conf"
    # Sauvegarde avant modification : réflexe d'administration à garder.
    cp -a "$conf" "${conf}.bak.$(date +%Y%m%d-%H%M%S)"

    # On indique au serveur Zabbix le mot de passe de la base.
    # Le fichier gère les deux cas : ligne encore commentée (installation
    # neuve) ou déjà définie (ré-exécution du script).
    local pw_sed
    pw_sed=$(sed_escape "$DB_PASSWORD")
    if grep -qE '^DBPassword=' "$conf"; then
        sed -i -E "s|^DBPassword=.*|DBPassword=${pw_sed}|" "$conf"
    else
        sed -i -E "s|^# DBPassword=.*|DBPassword=${pw_sed}|" "$conf"
    fi

    # Ce fichier contient un secret : on vérifie que les droits restent stricts
    # (root + groupe zabbix uniquement, pas de lecture pour « les autres »).
    chown root:zabbix "$conf"
    chmod 640 "$conf"
    success "Serveur Zabbix configuré (${conf})."
}

#===============================================================================
# ÉTAPE 7 — NGINX + PHP-FPM (interface web)
#===============================================================================

configure_frontend() {
    CURRENT_STEP="configuration de NGINX et PHP-FPM"

    local nginx_conf="/etc/zabbix/nginx.conf"
    cp -a "$nginx_conf" "${nginx_conf}.bak.$(date +%Y%m%d-%H%M%S)"

    # Le paquet zabbix-nginx-conf livre un bloc « server » prêt à l'emploi,
    # avec les directives listen/server_name commentées : la procédure
    # officielle demande simplement de les décommenter et de les renseigner.
    # Les expressions gèrent aussi la ré-exécution (lignes déjà décommentées).
    local name_sed
    name_sed=$(sed_escape "$SERVER_NAME")
    sed -i -E "s|^#?[[:space:]]*listen[[:space:]]+[0-9]+;|        listen          ${LISTEN_PORT};|" "$nginx_conf"
    sed -i -E "s|^#?[[:space:]]*server_name[[:space:]]+.*;|        server_name     ${name_sed};|" "$nginx_conf"

    # Si l'utilisateur veut le port 80, le site NGINX par défaut de Debian
    # (page « Welcome to nginx ») écoute déjà dessus : on le désactive,
    # sinon NGINX refusera de démarrer (conflit d'adresse).
    if [[ "$LISTEN_PORT" == "80" && -e /etc/nginx/sites-enabled/default ]]; then
        warn "Port 80 choisi : désactivation du site NGINX par défaut (conflit d'écoute)."
        rm -f /etc/nginx/sites-enabled/default
        tip "Le fichier /etc/nginx/sites-available/default est conservé : le site"
        tip "par défaut peut être réactivé plus tard avec un lien symbolique."
    fi

    # Fuseau horaire PHP : recommandé par la documentation pour le frontend.
    local php_conf="/etc/zabbix/php-fpm.conf"
    if [[ -f "$php_conf" ]]; then
        cp -a "$php_conf" "${php_conf}.bak.$(date +%Y%m%d-%H%M%S)"
        local tz_sed
        tz_sed=$(sed_escape "$PHP_TIMEZONE")
        if grep -qE '^;?[[:space:]]*php_value\[date\.timezone\]' "$php_conf"; then
            sed -i -E "s|^;?[[:space:]]*php_value\[date\.timezone\][[:space:]]*=.*|php_value[date.timezone] = ${tz_sed}|" "$php_conf"
        else
            echo "php_value[date.timezone] = ${PHP_TIMEZONE}" >>"$php_conf"
        fi
    fi

    # Toujours valider la syntaxe AVANT de recharger NGINX : un « nginx -t »
    # évite de faire tomber le serveur web sur une faute de frappe.
    log "Validation de la configuration NGINX (nginx -t)..."
    if ! run_logged nginx -t; then
        error "La configuration NGINX est invalide. Détails dans ${LOG_FILE}."
        exit 1
    fi
    success "NGINX et PHP-FPM configurés (port ${LISTEN_PORT}, server_name ${SERVER_NAME})."
}

#===============================================================================
# ÉTAPE 8 — DÉMARRAGE DES SERVICES
#===============================================================================

# Le nom du service PHP-FPM dépend de la version de PHP livrée par Debian
# (8.2 sur Debian 12, 8.4 sur Debian 13). Plutôt que de coder ces numéros en
# dur — ce qui casserait à la prochaine version — on détecte ce qui est installé.
detect_php_fpm_service() {
    local ver
    ver=$(find /etc/php -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
    if [[ -z "$ver" ]]; then
        error "Aucune installation PHP détectée dans /etc/php."
        return 1
    fi
    printf 'php%s-fpm' "$ver"
}

start_services() {
    CURRENT_STEP="démarrage et activation des services"

    local php_fpm_service
    php_fpm_service=$(detect_php_fpm_service)
    log "Service PHP-FPM détecté : ${php_fpm_service}"

    local services=("zabbix-server" "$AGENT_SERVICE" "nginx" "$php_fpm_service")
    log "Redémarrage des services : ${services[*]}"
    run_logged systemctl restart "${services[@]}"

    # « enable » = démarrage automatique au boot : indispensable pour un
    # serveur de supervision, qui doit survivre à un redémarrage.
    log "Activation au démarrage du système..."
    run_logged systemctl enable "${services[@]}"
    success "Services démarrés et activés au boot."
}

#===============================================================================
# ÉTAPE 9 — PARE-FEU (nftables)
#===============================================================================

configure_firewall() {
    CURRENT_STEP="configuration du pare-feu"

    # Ce bloc est volontairement prudent : chaque serveur a sa propre politique
    # de pare-feu, et une règle ajoutée à l'aveugle échoue (ou pire, surprend).
    if ! command -v nft >/dev/null 2>&1; then
        log "nftables n'est pas installé : aucune règle de pare-feu à ajouter."
        tip "Si un pare-feu existe ailleurs (cloud, routeur), ouvrez le port TCP ${LISTEN_PORT}."
        return 0
    fi

    # On ne peut ajouter une règle que si la table/chaîne « inet filter input »
    # existe : l'ancienne version du script échouait silencieusement sinon.
    if nft list chain inet filter input >/dev/null 2>&1; then
        if nft list chain inet filter input | grep -q "tcp dport ${LISTEN_PORT} accept"; then
            log "La règle pare-feu pour le port ${LISTEN_PORT} existe déjà."
        else
            nft add rule inet filter input tcp dport "$LISTEN_PORT" accept
            success "Règle nftables ajoutée : port TCP ${LISTEN_PORT} autorisé."
        fi
        warn "Cette règle n'est PAS persistante : elle disparaîtra au redémarrage."
        tip  "Pour la rendre permanente, ajoutez-la dans /etc/nftables.conf puis"
        tip  "activez le service :  systemctl enable nftables"
    else
        log "Aucune chaîne « inet filter input » nftables : pas de pare-feu actif à ajuster."
    fi

    # Rappel important pour une architecture de supervision distribuée.
    tip "Pour superviser des machines DISTANTES, pensez aussi aux ports Zabbix :"
    tip "  • 10051/TCP entrant sur CE serveur (les agents lui envoient leurs données)"
    tip "  • 10050/TCP entrant sur chaque machine supervisée (contrôles passifs)"
}

#===============================================================================
# ÉTAPE 10 — VÉRIFICATIONS FINALES
#===============================================================================

verify_installation() {
    CURRENT_STEP="vérifications finales"

    local php_fpm_service all_ok="oui"
    php_fpm_service=$(detect_php_fpm_service)

    log "Vérification de l'état des services..."
    local svc
    for svc in zabbix-server "$AGENT_SERVICE" nginx "$php_fpm_service" mariadb; do
        # « is-active » est fait pour les scripts : code retour 0 = service actif
        # (contrairement à « systemctl status », pensé pour un humain).
        if systemctl is-active --quiet "$svc"; then
            success "Service ${svc} : actif."
        else
            error "Service ${svc} : INACTIF ou en erreur."
            tip   "Diagnostic :  systemctl status ${svc}  puis  journalctl -u ${svc} -n 50"
            all_ok="non"
        fi
    done

    log "Vérification de l'écoute sur le port ${LISTEN_PORT}..."
    if ss -tln | grep -q ":${LISTEN_PORT}[[:space:]]"; then
        success "Le port ${LISTEN_PORT} est bien en écoute."
    else
        error "Aucun service n'écoute sur le port ${LISTEN_PORT}."
        all_ok="non"
    fi

    # Test HTTP réel : plus parlant qu'un simple port ouvert, il prouve que
    # NGINX sert bien le frontend PHP de Zabbix.
    if command -v curl >/dev/null 2>&1; then
        log "Test HTTP du frontend (http://127.0.0.1:${LISTEN_PORT}/)..."
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:${LISTEN_PORT}/" || echo "000")
        if [[ "$http_code" =~ ^(200|30.)$ ]]; then
            success "Le frontend répond (HTTP ${http_code})."
        else
            warn "Réponse HTTP inattendue du frontend : ${http_code}."
            all_ok="non"
        fi
    fi

    if [[ "$all_ok" == "non" ]]; then
        warn "Au moins une vérification a échoué : consultez les messages ci-dessus et ${LOG_FILE}."
        warn "Journal du serveur Zabbix : /var/log/zabbix/zabbix_server.log"
    fi
}

#===============================================================================
# ÉTAPE 11 — RÉCAPITULATIF FINAL
#===============================================================================

final_summary() {
    CURRENT_STEP="récapitulatif final"

    # Adresse IP principale : pratique quand aucun DNS ne pointe vers le serveur.
    local ip_addr
    ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -n "$ip_addr" ]] || ip_addr="<adresse-IP-du-serveur>"

    tui_msgbox "Installation terminée !" \
"Zabbix ${ZABBIX_VERSION} LTS est installé sur ce serveur Debian ${DEBIAN_VERSION}.

ACCÈS À L'INTERFACE WEB :
  http://${SERVER_NAME}:${LISTEN_PORT}
  http://${ip_addr}:${LISTEN_PORT}

IDENTIFIANTS PAR DÉFAUT :
  Utilisateur : Admin        (A majuscule !)
  Mot de passe : zabbix

À FAIRE IMMÉDIATEMENT :
  1. Connectez-vous et CHANGEZ le mot de passe Admin :
     Utilisateurs > Admin > Modifier le mot de passe.
  2. Vérifiez l'hôte « Zabbix server » : il supervise déjà
     cette machine via l'agent installé (${AGENT_PACKAGE}).

Journal complet : ${LOG_FILE}
Documentation  : https://www.zabbix.com/documentation/${ZABBIX_VERSION}/fr/"

    echo ""
    success "Installation de Zabbix ${ZABBIX_VERSION} LTS terminée !"
    log     "Interface web : http://${SERVER_NAME}:${LISTEN_PORT}  ou  http://${ip_addr}:${LISTEN_PORT}"
    log     "Connexion : Admin / zabbix"
    tip     "Changez le mot de passe « Admin » dès la première connexion : c'est la"
    tip     "première chose que cherchera un attaquant sur une instance Zabbix exposée."
    tip     "Journal complet de l'installation : ${LOG_FILE}"
}

#===============================================================================
# PROGRAMME PRINCIPAL
# Chaque étape est une fonction : le script se lit comme la procédure officielle.
#===============================================================================

main() {
    preflight_checks         # 0. contrôles (root, Debian 12/13, réseau...)
    tui_collect_settings     # 1. questions à l'utilisateur (aucune modification)
    install_zabbix_repo      # 2. dépôt APT officiel Zabbix
    install_packages         # 3. paquets Zabbix + MariaDB
    secure_mariadb           # 4. durcissement de MariaDB
    create_database          # 5a. base « zabbix » + utilisateur
    import_schema            # 5b. schéma initial (~170 tables)
    configure_zabbix_server  # 6. mot de passe BDD dans zabbix_server.conf
    configure_frontend       # 7. NGINX (port, server_name) + fuseau PHP
    start_services           # 8. démarrage + activation au boot
    configure_firewall       # 9. règle nftables (si applicable) + conseils
    verify_installation      # 10. services, port, réponse HTTP
    final_summary            # 11. URL, identifiants, consignes de sécurité
}

main "$@"
