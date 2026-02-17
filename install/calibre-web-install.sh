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
  imagemagick \
  libpango-1.0-0 \
  libharfbuzz0b \
  libpangoft2-1.0-0 \
  fonts-liberation
msg_ok "Installed Dependencies"

msg_info "Installing Calibre (for eBook conversion)"
$STD apt install -y calibre
msg_ok "Installed Calibre"

fetch_and_deploy_gh_release "calibre-web" "janeczku/calibre-web" "tarball" "latest" "/opt/calibre-web"
setup_uv

msg_info "Installing Python Dependencies"
cd /opt/calibre-web
if ! $STD uv sync --no-dev; then
  msg_info "Retrying Python dependency install without build isolation"
  $STD uv venv
  $STD uv pip install --python /opt/calibre-web/.venv/bin/python --no-cache-dir calibreweb
  $STD uv sync --no-dev --no-build-isolation
fi
msg_ok "Installed Python Dependencies"

msg_info "Creating Service"
mkdir -p /opt/calibre-web/data
cat <<EOF >/etc/systemd/system/calibre-web.service
[Unit]
Description=Calibre-Web Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/calibre-web
ExecStart=/opt/calibre-web/.venv/bin/python /opt/calibre-web/cps.py
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
