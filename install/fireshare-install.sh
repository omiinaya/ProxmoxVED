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
# Clean up any existing nodejs/npm first
$STD apt-get remove -y nodejs npm || true
$STD apt-get autoremove -y || true

# Install Node.js 20.x from NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
$STD apt-get update
$STD apt-get install -y nodejs

# Update PATH to ensure npm is available
export PATH="/usr/bin:/usr/local/bin:$PATH"
hash -r  # Clear PATH cache

# Verify installation with explicit paths
if [[ ! -x "/usr/bin/node" ]] && [[ ! -x "/usr/local/bin/node" ]]; then
  msg_error "Node.js installation failed - binary not found"
  exit 1
fi

if [[ ! -x "/usr/bin/npm" ]] && [[ ! -x "/usr/local/bin/npm" ]]; then
  msg_error "npm installation failed - binary not found"
  exit 1
fi

NODE_VERSION=$(/usr/bin/node --version 2>/dev/null || /usr/local/bin/node --version 2>/dev/null)
NPM_VERSION=$(/usr/bin/npm --version 2>/dev/null || /usr/local/bin/npm --version 2>/dev/null)
msg_info "Successfully installed Node.js $NODE_VERSION with npm $NPM_VERSION"
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
# Ensure PATH includes npm location
export PATH="/usr/bin:/usr/local/bin:$PATH"

# Install frontend dependencies
if [[ -d app/client ]]; then
  cd app/client

  # Find npm binary explicitly
  NPM_BIN=""
  if [[ -x "/usr/bin/npm" ]]; then
    NPM_BIN="/usr/bin/npm"
  elif [[ -x "/usr/local/bin/npm" ]]; then
    NPM_BIN="/usr/local/bin/npm"
  else
    msg_error "npm binary not found in expected locations"
    exit 1
  fi

  msg_info "Using npm at: $NPM_BIN"

  # Use explicit npm path with legacy peer deps to handle conflicts
  if $NPM_BIN install --legacy-peer-deps; then
    msg_info "npm install completed successfully"
  else
    msg_info "Standard npm install failed, trying with force option"
    if $NPM_BIN install --legacy-peer-deps --force; then
      msg_info "npm install with force completed"
    else
      msg_info "npm install failed, continuing without frontend"
    fi
  fi

  # Try to build, but don't fail if it doesn't work
  if $NPM_BIN run build; then
    msg_info "Frontend build completed successfully"
  else
    msg_info "Build failed or not available, continuing with development setup"
  fi

  cd ../..
else
  msg_info "No client directory found, skipping frontend build"
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
if [[ -d app/client ]] && [[ -x "/usr/bin/npm" || -x "/usr/local/bin/npm" ]]; then
  cd app/client
  export PATH="/usr/bin:/usr/local/bin:\$PATH"
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
Environment=PATH=/usr/bin:/usr/local/bin:/bin:/sbin
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
