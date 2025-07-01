#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar (omiinaya)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
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
  git \
  python3-dev \
  python3-pip \
  python3-venv \
  ffmpeg \
  jq
msg_ok "Installed Dependencies"

NODE_VERSION="20" install_node_and_modules

msg_info "Installing ${APPLICATION}"
RELEASE_TAG=$(curl -s https://api.github.com/repos/ShaneIsrael/fireshare/releases/latest | jq -r .tag_name)
RELEASE_VERSION=$(echo "$RELEASE_TAG" | sed 's/^v//')

curl -fsSL "https://github.com/ShaneIsrael/fireshare/archive/refs/tags/${RELEASE_TAG}.tar.gz" | tar -xzf - -C /opt
mv "/opt/fireshare-${RELEASE_VERSION}" /opt/fireshare

cd /opt/fireshare
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install gunicorn
npm --prefix app/client install
npm --prefix app/client run build
flask db upgrade
deactivate
echo "${RELEASE_TAG}" >/opt/fireshare_version.txt
msg_ok "Installed ${APPLICATION}"

msg_info "Creating env, start script and service"
cat <<EOF >/opt/fireshare/.env
ADMIN_PASSWORD=password
EOF

cat <<EOF >/opt/fireshare/start.sh
#!/usr/bin/env bash
source /opt/fireshare/.venv/bin/activate
gunicorn --workers 4 -b 0.0.0.0:8080 "app.server:create_app()"
EOF
chmod +x /opt/fireshare/start.sh

cat <<EOF >/etc/systemd/system/fireshare.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/fireshare
EnvironmentFile=/opt/fireshare/.env
ExecStart=/opt/fireshare/start.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now fireshare.service
msg_ok "Created env, start script and service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
