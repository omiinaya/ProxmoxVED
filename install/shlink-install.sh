#!/usr/bin/env bash
# Shlink install script for Proxmox community-scripts
# Author: Omar Minaya
# License: MIT

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Adding PHP 8.4 Repository"
apt-get install -y apt-transport-https lsb-release ca-certificates curl || { msg_error "Failed to install prerequisites"; exit 1; }
curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg || { msg_error "Failed to add PHP GPG key"; exit 1; }
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
apt-get update || { msg_error "apt-get update failed"; exit 1; }

msg_info "Installing dependencies (Apache, PHP 8.4, MySQL client, unzip, curl)"
apt-get install -y apache2 php8.4 php8.4-cli php8.4-fpm php8.4-curl php8.4-pdo php8.4-intl php8.4-gd php8.4-gmp php8.4-apcu php8.4-xml php8.4-mysql unzip curl mariadb-client || { msg_error "Failed to install dependencies"; exit 1; }

msg_info "Downloading Shlink distributable"
cd /opt
LATEST_URL=$(curl -s https://api.github.com/repos/shlinkio/shlink/releases/latest | grep browser_download_url | grep dist | grep php8.4 | cut -d '"' -f 4 | head -n 1)
curl -L -o shlink-dist.zip "$LATEST_URL" || { msg_error "Failed to download Shlink"; exit 1; }
TEMP_DIR="/opt/shlink_temp"
mkdir -p "$TEMP_DIR"
unzip -q shlink-dist.zip -d "$TEMP_DIR" || { msg_error "Failed to unzip Shlink"; exit 1; }
rm shlink-dist.zip
# Find the extracted directory
EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "shlink*_php8.4_dist" | head -n 1)
if [[ -z "$EXTRACTED_DIR" ]]; then
    msg_error "Failed to find extracted Shlink directory!"
    exit 1
fi
rm -rf /opt/shlink
mv "$EXTRACTED_DIR" /opt/shlink
rm -rf "$TEMP_DIR"

# Ensure /opt/shlink/data exists
mkdir -p /opt/shlink/data

msg_info "Setting permissions"
chown -R www-data:www-data /opt/shlink
chmod -R 775 /opt/shlink/data

msg_info "Configuring Apache for Shlink"
cat <<EOF >/etc/apache2/sites-available/shlink.conf
<VirtualHost *:80>
    ServerName shlink.local
    DocumentRoot /opt/shlink/public
    <Directory /opt/shlink/public>
        Options FollowSymLinks Includes ExecCGI
        AllowOverride all
        Require all granted
    </Directory>
    ErrorLog \\${APACHE_LOG_DIR}/shlink_error.log
    CustomLog \\${APACHE_LOG_DIR}/shlink_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf
a2ensite shlink.conf
a2enmod rewrite
systemctl reload apache2

msg_info "Configuring MySQL database credentials (using defaults)"
SHLINK_DB_NAME="shlinkdb"
SHLINK_DB_USER="shlinkuser"
SHLINK_DB_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)"
SHLINK_DB_HOST="localhost"

# Store credentials in ~/shlink.creds
cat <<EOF > ~/shlink.creds
Shlink MySQL Credentials
-----------------------
Database: $SHLINK_DB_NAME
Username: $SHLINK_DB_USER
Password: $SHLINK_DB_PASSWORD
Host:     $SHLINK_DB_HOST
EOF
chmod 600 ~/shlink.creds

msg_info "Creating .env file for Shlink"
cat <<EOF >/opt/shlink/.env
SHLINK_DB_DRIVER=mysql
SHLINK_DB_NAME=$SHLINK_DB_NAME
SHLINK_DB_USER=$SHLINK_DB_USER
SHLINK_DB_PASSWORD=$SHLINK_DB_PASSWORD
SHLINK_DB_HOST=$SHLINK_DB_HOST
SHLINK_DB_PORT=3306
SHLINK_BASE_URL=http://localhost
SHLINK_DEFAULT_SHORT_CODES_LENGTH=5
SHLINK_DEFAULT_DOMAIN=localhost
EOF
chown www-data:www-data /opt/shlink/.env
chmod 600 /opt/shlink/.env

msg_info "Running Shlink installer (interactive)"
sudo -u www-data php /opt/shlink/vendor/bin/shlink-installer install
msg_ok "Shlink installation complete. Access via http://<container-ip>"

motd_ssh
customize

msg_info "Cleaning up"
apt-get -y autoremove
apt-get -y autoclean
msg_ok "Cleaned"
