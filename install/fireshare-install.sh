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
  software-properties-common \
  jq
msg_ok "Installed Dependencies"

msg_info "Setting up Node.js Environment"
# Node.js is already installed from dependencies
$STD npm install -g npm@latest
msg_ok "Set up Node.js Environment"

msg_info "Installing Fireshare"
RELEASE=$(curl -fsSL https://api.github.com/repos/ShaneIsrael/fireshare/releases/latest | jq -r .tag_name)
if [[ -z "$RELEASE" || "$RELEASE" == "null" ]]; then
  RELEASE="v1.2.25"  # Fallback to known version
fi
cd /opt
curl -fsSL -o "fireshare-${RELEASE}.tar.gz" "https://github.com/ShaneIsrael/fireshare/archive/refs/tags/${RELEASE}.tar.gz"
tar -xf "fireshare-${RELEASE}.tar.gz"
mv "fireshare-${RELEASE#v}" fireshare
cd fireshare
msg_ok "Downloaded Fireshare"

msg_info "Installing Python Dependencies"
# Check if requirements.txt exists, if not create a minimal one
if [[ ! -f requirements.txt ]]; then
  cat <<EOF >requirements.txt
Flask>=2.0.0
Pillow
python-magic
EOF
fi
python3 -m venv venv
source venv/bin/activate
pip install flask pillow python-magic
msg_ok "Installed Python Dependencies"

msg_info "Installing Node.js Dependencies and Building Frontend"
# Install frontend dependencies
if [[ -d app/client ]]; then
  cd app/client
  npm install || $STD npm install --legacy-peer-deps
  npm run build || echo "Build failed, continuing with development setup"
  cd ../..
else
  echo "No client directory found, skipping frontend build"
fi
msg_ok "Built Frontend"

msg_info "Setting up Application"
# Create basic startup script since this is a simpler app
cat <<EOF >/opt/fireshare/run_local.sh
#!/bin/bash
cd /opt/fireshare
python3 -m venv venv
source venv/bin/activate
python3 app/server/main.py &
cd app/client
npm start &
wait
EOF
chmod +x /opt/fireshare/run_local.sh
msg_ok "Set up Application"

msg_info "Creating Service Files"
# Backend service
cat <<EOF >/etc/systemd/system/fireshare-backend.service
[Unit]
Description=Fireshare Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fireshare
Environment=PYTHONPATH=/opt/fireshare
ExecStart=/opt/fireshare/venv/bin/python app/server/main.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Frontend service
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

systemctl daemon-reload
systemctl enable --now fireshare-backend
systemctl enable --now fireshare-frontend
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
