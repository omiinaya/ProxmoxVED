#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kevinanielsen/go-fast-cdn

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
  unzip \
  jq
msg_ok "Installed Dependencies"

msg_info "Installing Go Fast CDN"
RELEASE=$(curl -fsSL https://api.github.com/repos/kevinanielsen/go-fast-cdn/releases/latest | jq -r .tag_name)
if [[ -z "$RELEASE" || "$RELEASE" == "null" ]]; then
  RELEASE="v0.1.6"  # Fallback to known version
fi

mkdir -p /opt/go-fast-cdn
cd /tmp
curl -fsSL -o "go-fast-cdn_${RELEASE#v}_linux_amd64.zip" "https://github.com/kevinanielsen/go-fast-cdn/releases/download/${RELEASE}/go-fast-cdn_${RELEASE#v}_linux_amd64.zip"
unzip "go-fast-cdn_${RELEASE#v}_linux_amd64.zip"
mv go-fast-cdn /opt/go-fast-cdn/
chmod +x /opt/go-fast-cdn/go-fast-cdn

# Create data directories
mkdir -p /opt/go-fast-cdn/data
mkdir -p /opt/go-fast-cdn/uploads
chown -R root:root /opt/go-fast-cdn
chmod -R 755 /opt/go-fast-cdn
msg_ok "Installed Go Fast CDN"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/go-fast-cdn.service
[Unit]
Description=Go Fast CDN
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/go-fast-cdn
ExecStart=/opt/go-fast-cdn/go-fast-cdn
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now go-fast-cdn
msg_ok "Created and Started Service"

echo "${RELEASE}" >/opt/${APP}_version.txt

motd_ssh
customize

msg_info "Cleaning up"
rm -f /tmp/go-fast-cdn_${RELEASE#v}_linux_amd64.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
