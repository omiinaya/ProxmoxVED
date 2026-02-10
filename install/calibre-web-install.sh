#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: mikolaj92
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/janeczku/calibre-web

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  python3 \
  python3-pip \
  imagemagick \
  libpango-1.0-0 \
  libharfbuzz0b \
  libpangoft2-1.0-0 \
  fonts-liberation
msg_ok "Installed Dependencies"

msg_info "Installing Calibre (for eBook conversion)"
$STD apt install -y calibre
msg_ok "Installed Calibre"

msg_info "Setting up Calibre-Web"
fetch_and_deploy_gh_release "calibre-web" "janeczku/calibre-web" "tarball" "latest" "/opt/calibre-web"
msg_ok "Setup Calibre-Web"

msg_info "Installing Python Dependencies"
cd /opt/calibre-web
$STD pip3 install --no-cache-dir -r requirements.txt
msg_ok "Installed Python Dependencies"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/calibre-web.service
mkdir -p /opt/calibre-web/data
[Unit]
Description=Calibre-Web Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/calibre-web
ExecStart=/usr/bin/python3 /opt/calibre-web/cps.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now calibre-web
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
