#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tomfrenzel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP_SLUG="sparkyfitness"
APP_DIR="/opt/${APP_SLUG}"
CONFIG_DIR="/etc/${APP_SLUG}"
DATA_DIR="/var/lib/${APP_SLUG}"
WEB_DIR="/var/www/${APP_SLUG}"
APP_USER="${APP_SLUG}"
APP_GROUP="${APP_SLUG}"

DB_NAME="sparkyfitness_db"
DB_USER="sparky"
DB_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)"
APP_DB_USER="sparky_app"
APP_DB_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)"
API_ENCRYPTION_KEY="$(openssl rand -hex 32)"
BETTER_AUTH_SECRET="$(openssl rand -hex 32)"

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

NODE_VERSION="20" setup_nodejs
PG_VERSION="15" setup_postgresql
PG_DB_NAME="${DB_NAME}" PG_DB_USER="${DB_USER}" PG_DB_PASS="${DB_PASS}" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

fetch_and_deploy_gh_release "${APP_SLUG}" "CodeWithCJ/SparkyFitness" "tarball" "latest" "${APP_DIR}"

msg_info "Configuring Sparky Fitness"
$STD useradd -r -m -d "${DATA_DIR}" -s /usr/sbin/nologin "${APP_USER}"
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${DATA_DIR}/uploads" "${DATA_DIR}/backup" "${WEB_DIR}"
cp "${APP_DIR}/docker/.env.example" "${CONFIG_DIR}/.env"

sed -i "s|^SPARKY_FITNESS_DB_NAME=.*|SPARKY_FITNESS_DB_NAME=${DB_NAME}|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_DB_USER=.*|SPARKY_FITNESS_DB_USER=${DB_USER}|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_DB_PASSWORD=.*|SPARKY_FITNESS_DB_PASSWORD=${DB_PASS}|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_APP_DB_USER=.*|SPARKY_FITNESS_APP_DB_USER=${APP_DB_USER}|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_APP_DB_PASSWORD=.*|SPARKY_FITNESS_APP_DB_PASSWORD=${APP_DB_PASS}|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_DB_HOST=.*|SPARKY_FITNESS_DB_HOST=localhost|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_SERVER_HOST=.*|SPARKY_FITNESS_SERVER_HOST=localhost|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_SERVER_PORT=.*|SPARKY_FITNESS_SERVER_PORT=3010|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_FRONTEND_URL=.*|SPARKY_FITNESS_FRONTEND_URL=http://${LOCAL_IP}:80|" "${CONFIG_DIR}/.env"
sed -i "s|^SPARKY_FITNESS_API_ENCRYPTION_KEY=.*|SPARKY_FITNESS_API_ENCRYPTION_KEY=${API_ENCRYPTION_KEY}|" "${CONFIG_DIR}/.env"
sed -i "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}|" "${CONFIG_DIR}/.env"
sed -i "s|^# SERVER_BACKUP_PATH=.*|SERVER_BACKUP_PATH=${DATA_DIR}/backup|" "${CONFIG_DIR}/.env"
sed -i "s|^# SERVER_UPLOADS_PATH=.*|SERVER_UPLOADS_PATH=${DATA_DIR}/uploads|" "${CONFIG_DIR}/.env"

cp "${CONFIG_DIR}/.env" "${APP_DIR}/.env"
mkdir -p "${DATA_DIR}/uploads" "${DATA_DIR}/backup"
chmod 640 "${CONFIG_DIR}/.env"
msg_ok "Configured Sparky Fitness"

msg_info "Building Backend"
cd "${APP_DIR}/SparkyFitnessServer"
$STD npm install
msg_ok "Built Backend"

msg_info "Building Frontend"
cd "${APP_DIR}/SparkyFitnessFrontend"
$STD npm install
$STD npm run build
cp -a "${APP_DIR}/SparkyFitnessFrontend/dist/." "${WEB_DIR}/"
msg_ok "Built Frontend"

msg_info "Configuring Nginx"
sed \
  -e 's|${SPARKY_FITNESS_SERVER_HOST}|127.0.0.1|g' \
  -e 's|${SPARKY_FITNESS_SERVER_PORT}|3010|g' \
  -e 's|root /usr/share/nginx/html;|root /var/www/sparkyfitness;|g' \
  -e 's|server_name localhost;|server_name _;|g' \
  "${APP_DIR}/docker/nginx.conf" >/etc/nginx/sites-available/${APP_SLUG}
ln -sf /etc/nginx/sites-available/${APP_SLUG} /etc/nginx/sites-enabled/${APP_SLUG}
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/sparkyfitness-server.service
[Unit]
Description=SparkyFitness Backend Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}/SparkyFitnessServer
EnvironmentFile=${CONFIG_DIR}/.env
ExecStart=/usr/bin/node SparkyFitnessServer.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chown -R ${APP_USER}:${APP_GROUP} "${APP_DIR}" "${DATA_DIR}" "${CONFIG_DIR}"
chmod -R 755 "${WEB_DIR}"

$STD systemctl daemon-reload
$STD systemctl enable --now sparkyfitness-server
$STD systemctl enable --now nginx
msg_ok "Created Services"

cat <<EOF >~/sparkyfitness.creds
SparkyFitness Database Credentials
Database Name: ${DB_NAME}
Database User: ${DB_USER}
Database Password: ${DB_PASS}
App Database User: ${APP_DB_USER}
App Database Password: ${APP_DB_PASS}
EOF

motd_ssh
customize
cleanup_lxc
