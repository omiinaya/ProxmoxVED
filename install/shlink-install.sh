#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Adapted for Shlink
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/shlinkio/shlink

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    curl \
    unzip \
    apache2 \
    jq
msg_ok "Installed Dependencies"

PHP_VERSION=8.5
PHP_MODULE=curl,pdo,intl,gd,gmp,apcu,xml,sqlite3
PHP_APACHE=YES

msg_info "Setting Up Non-Root User"
$STD useradd -m -s /bin/bash shlink
$STD mkdir -p /opt/shlink
$STD chown shlink:shlink /opt/shlink
msg_ok "Set Up Non-Root User"

msg_info "Installing Shlink"
$STD a2enmod rewrite
RELEASE=$(curl -fsSL https://api.github.com/repos/shlinkio/shlink/releases/latest | jq -r .tag_name | sed 's/^v//')
curl -fsSL -o "/tmp/shlink-${RELEASE}-php8.4-dist.zip" "https://github.com/shlinkio/shlink/releases/download/v${RELEASE}/shlink-${RELEASE}-php8.4-dist.zip"
$STD unzip -q "/tmp/shlink-${RELEASE}-php8.4-dist.zip" -d /opt/shlink
$STD chown -R shlink:shlink /opt/shlink
$STD chmod -R u+w /opt/shlink/data
msg_ok "Installed Shlink"

msg_info "Configuring Shlink"
# Set env vars for non-interactive installer
cat <<EOF >/opt/shlink/.env
SHLINK_DB_DRIVER=sqlite
SHLINK_DB_NAME=/opt/shlink/data/database.sqlite
SHLINK_BASE_URL=http://localhost
SHLINK_DEFAULT_SHORT_CODES_LENGTH=5
SHLINK_DEFAULT_DOMAIN=localhost
EOF
$STD chown shlink:shlink /opt/shlink/.env
$STD chmod 600 /opt/shlink/.env
# Run installer
su - shlink -c "cd /opt/shlink && php vendor/bin/shlink-installer install" | tee -a ~/shlink-install.log
msg_ok "Configured Shlink"

msg_info "Configuring Apache2"
cat <<EOF >/etc/apache2/sites-available/shlink.conf
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot "/opt/shlink/public"

    <Directory "/opt/shlink/public">
        Options FollowSymLinks Includes ExecCGI
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
$STD a2dissite 000-default.conf
$STD a2ensite shlink.conf
$STD systemctl restart apache2
msg_ok "Configured Apache2"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/shlink.service
[Unit]
Description=Shlink URL Shortener
After=network.target

[Service]
User=shlink
Group=shlink
WorkingDirectory=/opt/shlink
ExecStart=/usr/bin/php -S 0.0.0.0:8080 public/index.php
Restart=always

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable shlink
$STD systemctl start shlink
msg_ok "Service Created"

motd_ssh
customize

msg_info "Cleaning up"
$STD rm -f "/tmp/shlink-${RELEASE}-php8.4-dist.zip"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
