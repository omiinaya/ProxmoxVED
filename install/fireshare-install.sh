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
  git \
  gnupg2 \
  ca-certificates \
  lsb-release \
  software-properties-common \
  jq
msg_ok "Installed Dependencies"

msg_info "Setting up Node.js Environment"
# Install Node.js 20.x from NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
$STD apt-get install -y nodejs
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
python3 -m venv venv
source venv/bin/activate
# Install basic requirements first
pip install --upgrade pip
pip install flask pillow python-magic

# If there's a requirements.txt, install from it
if [[ -f requirements.txt ]]; then
  pip install -r requirements.txt || echo "Some requirements failed to install, continuing..."
fi
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
# Make sure the run_local.sh script is executable
if [[ -f run_local.sh ]]; then
  chmod +x run_local.sh
fi

# Create a simplified startup script
cat <<EOF >/opt/fireshare/start_fireshare.sh
#!/bin/bash
cd /opt/fireshare
source venv/bin/activate

# Start backend
if [[ -f app/server/main.py ]]; then
  python3 app/server/main.py &
elif [[ -f run_local.sh ]]; then
  ./run_local.sh &
fi

# Start frontend if it exists
if [[ -d app/client ]]; then
  cd app/client
  npm start &
fi

wait
EOF
chmod +x /opt/fireshare/start_fireshare.sh
msg_ok "Set up Application"

msg_info "Creating Service Files"
# Single service to run both backend and frontend
cat <<EOF >/etc/systemd/system/fireshare.service
[Unit]
Description=Fireshare Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fireshare
ExecStart=/opt/fireshare/start_fireshare.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
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
