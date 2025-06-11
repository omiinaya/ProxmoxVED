#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ShaneIsrael/fireshare

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
  sudo \
  mc \
  python3 \
  python3-pip \
  python3-venv \
  nodejs \
  npm \
  git \
  gnupg2 \
  ca-certificates \
  lsb-release \
  software-properties-common
msg_ok "Installed Dependencies"

msg_info "Setting up Node.js Environment"
# Install specific Node.js version via NodeSource
# curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
$STD apt-get install -y nodejs
msg_ok "Set up Node.js Environment"

msg_info "Installing Fireshare"
RELEASE=$(curl -fsSL https://api.github.com/repos/ShaneIsrael/fireshare/releases/latest | jq -r .tag_name)
cd /opt
curl -fsSL -o "fireshare-${RELEASE}.tar.gz" "https://github.com/ShaneIsrael/fireshare/archive/refs/tags/${RELEASE}.tar.gz"
tar -xf "fireshare-${RELEASE}.tar.gz"
mv "fireshare-${RELEASE#v}" fireshare
cd fireshare
msg_ok "Downloaded Fireshare"

msg_info "Installing Python Dependencies"
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt || true
msg_ok "Installed Python Dependencies"

msg_info "Installing Node.js Dependencies and Building Frontend"
npm install
cd app/client
npm install
npm run build
cd ../..
msg_ok "Built Frontend"

msg_info "Setting up Database"
cd app/server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 manage.py migrate
cd ../..
msg_ok "Set up Database"

msg_info "Creating Admin User"
cd app/server
source venv/bin/activate
echo "from django.contrib.auth.models import User; User.objects.filter(username='admin').exists() or User.objects.create_superuser('admin', 'admin@example.com', 'admin')" | python3 manage.py shell
cd ../..
msg_ok "Created Admin User"

msg_info "Creating Service Files"
# Backend service
cat <<EOF >/etc/systemd/system/fireshare-backend.service
[Unit]
Description=Fireshare Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fireshare/app/server
Environment=PYTHONPATH=/opt/fireshare/app/server
ExecStart=/opt/fireshare/app/server/venv/bin/python manage.py runserver 0.0.0.0:8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Frontend service (for development server)
cat <<EOF >/etc/systemd/system/fireshare-frontend.service
[Unit]
Description=Fireshare Frontend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fireshare/app/client
ExecStart=/usr/bin/npm start
Environment=PORT=3000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Main service to serve the built frontend
cat <<EOF >/etc/systemd/system/fireshare.service
[Unit]
Description=Fireshare Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fireshare
ExecStart=/usr/bin/python3 -m http.server 3000 --directory app/client/build
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now fireshare-backend
systemctl enable --now fireshare
msg_ok "Created and Started Services"

msg_info "Creating Data Directories"
mkdir -p /opt/fireshare/data
mkdir -p /opt/fireshare/processed
mkdir -p /opt/fireshare/videos
chown -R root:root /opt/fireshare
msg_ok "Created Data Directories"

echo "${RELEASE}" >/opt/${APP}_version.txt

motd_ssh
customize

msg_info "Cleaning up"
rm -f /opt/fireshare-${RELEASE}.tar.gz
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
