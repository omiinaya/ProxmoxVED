#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (MickLesk)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://linkding.link/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  pkg-config \
  python3-dev \
  nginx \
  libpq-dev \
  libicu-dev \
  libsqlite3-dev \
  libffi-dev
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
setup_uv
fetch_and_deploy_gh_release "linkding" "sissbruecker/linkding"

msg_info "Building Frontend"
cd /opt/linkding
$STD npm ci
$STD npm run build
msg_ok "Built Frontend"

msg_info "Compiling SQLite ICU Extension"
cd /tmp
SQLITE_RELEASE_YEAR=2023
SQLITE_RELEASE=3430000
$STD wget https://www.sqlite.org/${SQLITE_RELEASE_YEAR}/sqlite-amalgamation-${SQLITE_RELEASE}.zip
$STD unzip -o sqlite-amalgamation-${SQLITE_RELEASE}.zip
cp sqlite-amalgamation-${SQLITE_RELEASE}/sqlite3.h .
cp sqlite-amalgamation-${SQLITE_RELEASE}/sqlite3ext.h .
$STD wget "https://www.sqlite.org/src/raw/ext/icu/icu.c?name=91c021c7e3e8bbba286960810fa303295c622e323567b2e6def4ce58e4466e60" -O icu.c
$STD gcc -fPIC -shared icu.c $(pkg-config --libs --cflags icu-uc icu-io) -o /opt/linkding/libicu.so
rm -rf sqlite-amalgamation-${SQLITE_RELEASE}* icu.c sqlite3.h sqlite3ext.h
cd /opt/linkding
msg_ok "Compiled SQLite ICU Extension"

msg_info "Setting up linkding"
rm -f bookmarks/settings/dev.py
touch bookmarks/settings/custom.py
$STD uv sync --no-dev --frozen
$STD uv pip install gunicorn
mkdir -p data/{favicons,previews,assets}
ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
cat <<EOF >/opt/linkding/.env
LD_SUPERUSER_NAME=admin
LD_SUPERUSER_PASSWORD=${ADMIN_PASS}
LD_CSRF_TRUSTED_ORIGINS=http://${LOCAL_IP}:9090
EOF
set -a && source /opt/linkding/.env && set +a
$STD /opt/linkding/.venv/bin/python manage.py generate_secret_key
$STD /opt/linkding/.venv/bin/python manage.py migrate
$STD /opt/linkding/.venv/bin/python manage.py enable_wal
$STD /opt/linkding/.venv/bin/python manage.py create_initial_superuser
$STD /opt/linkding/.venv/bin/python manage.py collectstatic --no-input
msg_ok "Set up linkding"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/linkding.service
[Unit]
Description=linkding Bookmark Manager
After=network.target

[Service]
User=root
WorkingDirectory=/opt/linkding
EnvironmentFile=/opt/linkding/.env
ExecStart=/opt/linkding/.venv/bin/gunicorn \
  --bind 127.0.0.1:8000 \
  --workers 3 \
  --threads 2 \
  --timeout 120 \
  bookmarks.wsgi:application
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/linkding-tasks.service
[Unit]
Description=linkding Background Tasks
After=network.target

[Service]
User=root
WorkingDirectory=/opt/linkding
EnvironmentFile=/opt/linkding/.env
ExecStart=/opt/linkding/.venv/bin/python manage.py run_huey
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<'EOF' >/etc/nginx/sites-available/linkding
server {
    listen 9090;
    server_name _;

    client_max_body_size 20M;

    location /static/ {
        alias /opt/linkding/static/;
        expires 30d;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
    }
}
EOF
$STD rm -f /etc/nginx/sites-enabled/default
$STD ln -sf /etc/nginx/sites-available/linkding /etc/nginx/sites-enabled/linkding
systemctl enable -q --now nginx linkding linkding-tasks
systemctl restart nginx
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
