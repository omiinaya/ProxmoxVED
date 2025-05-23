#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
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

msg_info "Installing ConvertX"
$STD curl -fsSL "https://bun.sh/install" | bash
$STD git clone "https://github.com/C4illin/ConvertX.git" /opt/convertx
cd /opt/convertx
$STD bun install
cat <<EOF >/opt/convertx/.env
PORT=3000
EOF
msg_ok "Installed ConvertX"

msg_info "Starting ConvertX"
cat <<EOF >/etc/systemd/system/convertx.service
[Unit]
Description=ConvertX File Converter
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/convertx
EnvironmentFile=/opt/convertx/.env
ExecStart=/root/.bun/bin/bun dev
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
