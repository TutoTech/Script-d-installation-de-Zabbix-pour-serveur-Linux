#!/bin/bash

# Script d'installation et configuration de Zabbix 7.0 sur Debian 12
# Basé strictement sur la documentation officielle Zabbix

# Variables
DB_PASSWORD="Popopo@000"  # Mot de passe pour la base de données Zabbix
SERVER_NAME="zabbix.example.com"    # Nom du serveur pour Nginx
ZABBIX_LISTEN_PORT="8080"    # Port d'écoute pour Nginx

# Fonction pour afficher des messages colorés
INFO="\033[1;34m[INFO]\033[0m"
SUCCESS="\033[1;32m[SUCCESS]\033[0m"
ERROR="\033[1;31m[ERROR]\033[0m"
RESET="\033[0m"

# Mise à jour des paquets
echo -e "$INFO Mise à jour des paquets..."
apt update -y

# Étape 1 : Installer le référentiel Zabbix
echo -e "$INFO Installation du référentiel Zabbix..."
wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian12_all.deb
if dpkg -i zabbix-release_latest_7.0+debian12_all.deb; then
    echo -e "$SUCCESS Référentiel Zabbix installé."
else
    echo -e "$ERROR Impossible d'installer le référentiel Zabbix."
    exit 1
fi
apt update -y

# Étape 2 : Installer Zabbix Server, Frontend et Agent
echo -e "$INFO Installation des paquets Zabbix..."
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent
if [ $? -eq 0 ]; then
    echo -e "$SUCCESS Paquets Zabbix installés."
else
    echo -e "$ERROR Échec de l'installation des paquets Zabbix."
    exit 1
fi

# Étape 3 : Installation et configuration de MariaDB
echo -e "$INFO Installation de MariaDB..."
apt install -y mariadb-server

# Sécurisation de MariaDB
mysql_secure_installation

# Création de la base de données Zabbix
echo -e "$INFO Configuration de la base de données Zabbix..."
mysql -uroot -p << EOF
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER zabbix@localhost IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON zabbix.* TO zabbix@localhost;
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

# Importer le schéma de base de données Zabbix
echo -e "$INFO Importation du schéma de base de données Zabbix..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p$DB_PASSWORD zabbix

# Désactiver log_bin_trust_function_creators
echo -e "$INFO Désactivation de log_bin_trust_function_creators..."
mysql -uroot -p << EOF
SET GLOBAL log_bin_trust_function_creators = 0;
FLUSH PRIVILEGES;
EOF

# Étape 4 : Configurer Zabbix Server
echo -e "$INFO Configuration de Zabbix Server..."
sed -i "s/# DBPassword=/DBPassword=$DB_PASSWORD/" /etc/zabbix/zabbix_server.conf

# Étape 5 : Configurer PHP pour l'interface Zabbix
echo -e "$INFO Configuration de Nginx pour Zabbix..."
sed -i "s/^\(\s*\)#\s*listen\s*8080;/\1listen 8080;/" /etc/zabbix/nginx.conf
sed -i "s/^\(\s*\)#\s*server_name\s*example.com;/\1server_name $SERVER_NAME;/" /etc/zabbix/nginx.conf

# Rétablir l'indentation si nécessaire
echo -e "$INFO Rétablissement de l'indentation..."
sed -i 's/^\(\s*\)listen 8080;/        listen 8080;/' /etc/zabbix/nginx.conf
sed -i 's/^\(\s*\)server_name example.com;/        server_name example.com;/' /etc/zabbix/nginx.conf

# Vérification de la configuration Nginx
echo -e "$INFO Validation de la configuration Nginx..."
if nginx -t; then
    echo -e "$SUCCESS Configuration Nginx valide."
else
    echo -e "$ERROR Erreur dans la configuration Nginx. Veuillez vérifier /etc/zabbix/nginx.conf."
    exit 1
fi

# Étape 6 : Redémarrer les services
echo -e "$INFO Redémarrage des services..."
systemctl restart zabbix-server zabbix-agent nginx php8.2-fpm
systemctl enable zabbix-server zabbix-agent nginx php8.2-fpm

# Étape 7 : Ouverture des ports via nftables
nft add rule inet filter input tcp dport $ZABBIX_LISTEN_PORT accept && echo -e "$SUCCESS Pare-feu nftables configuré pour autoriser le port $ZABBIX_LISTEN_PORT."


# Vérification des services
echo -e "$INFO Souhaitez-vous vérifier l'état des services ? (oui/non)"
read verify_services

if [ "$verify_services" = "oui" ]; then
    # Fonction pour vérifier l'état d'un service
    check_service() {
        local service_name=$1
        local service_label=$2
        echo -e "$INFO Vérification du service $service_label..."
        if systemctl status "$service_name" --no-pager | grep -q 'Active:'; then
            echo -e "$SUCCESS Le service $service_label est actif."
        else
            echo -e "$ERROR Le service $service_label est inactif ou en erreur."
        fi
    }

    # Vérification des services
    check_service "nginx" "Nginx"
    check_service "php8.2-fpm" "PHP-FPM"
    check_service "zabbix-server" "Zabbix Server"
    check_service "zabbix-agent" "Zabbix Agent"

    # Vérification du port Zabbix
    echo -e "$INFO Vérification que le port $ZABBIX_LISTEN_PORT est actif..."
    if ss -tuln | grep -q ":$ZABBIX_LISTEN_PORT"; then
        echo -e "$SUCCESS Le port $ZABBIX_LISTEN_PORT est ouvert et à l'écoute."
    else
        echo -e "$ERROR Le port $ZABBIX_LISTEN_PORT n'est pas actif. Vérifiez la configuration."
    fi
fi

# Étape finale : Instructions
echo -e "$SUCCESS Zabbix a été installé avec succès !"
echo -e "$INFO Accédez à l'interface web de Zabbix via : http://$SERVER_NAME:$ZABBIX_LISTEN_PORT ou http://<adresse_IP>:$ZABBIX_LISTEN_PORT"
echo -e "$INFO Utilisez l'utilisateur 'Admin' avec le mot de passe 'zabbix' par défaut."
