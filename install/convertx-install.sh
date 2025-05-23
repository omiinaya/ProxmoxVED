#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Adapted for ConvertX
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/C4illin/ConvertX

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git curl ffmpeg
msg_ok "Installed Dependencies"

msg_info "Installing Bun"
$STD curl -fsSL https://bun.sh/install | bash
$STD ln -sf /root/.bun/bin/bun /usr/local/bin/bun
msg_ok "Installed Bun"

msg_info "Cloning ConvertX Repository"
$STD git clone https://github.com/C4illin/ConvertX.git /opt/convertx
cd /opt/convertx
msg_ok "Cloned ConvertX Repository"

msg_info "Installing ConvertX Dependencies"
$STD bun install
msg_ok "Installed ConvertX Dependencies"

msg_info "Configuring ConvertX"
# Generate a random JWT_SECRET
JWT_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
cat <<EOF >/opt/convertx/.env
JWT_SECRET=$JWT_SECRET
PORT=3000
EOF
$STD chown -R nobody:nogroup /opt/convertx
msg_ok "Configured ConvertX"

msg_info "Starting ConvertX"
# Create a systemd service for persistent running
cat <<EOF >/etc/systemd/system/convertx.service
[Unit]
Description=ConvertX File Converter
After=network.target

[Service]
User=nobody
WorkingDirectory=/opt/convertx
EnvironmentFile=/opt/convertx/.env
ExecStart=/usr/local/bin/bun run start
Restart=always

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable convertx.service
$STD systemctl start convertx.service
msg_ok "Started ConvertX"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
