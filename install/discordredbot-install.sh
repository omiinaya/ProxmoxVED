#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Adapted for Red Discord Bot
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Cog-Creators/Red-DiscordBot

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    python3 \
    python3-dev \
    python3-pip \
    git \
    openjdk-17-jre-headless \
    build-essential \
    nano
msg_ok "Installed Dependencies"

msg_info "Setting Up Non-Root User"
$STD useradd -m -s /bin/bash reduser
$STD mkdir -p /opt/redbot
$STD chown reduser:reduser /opt/redbot
msg_ok "Set Up Non-Root User"

msg_info "Installing Red Discord Bot"
$STD pip3 install -U pip wheel Red-DiscordBot
msg_ok "Installed Red Discord Bot"

msg_info "Configuring Red Discord Bot"
# Generate a random token if DISCORD_TOKEN is not set
if [[ -z "$DISCORD_TOKEN" ]]; then
    DISCORD_TOKEN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 59)
    echo "Warning: No DISCORD_TOKEN provided. Generated a placeholder: $DISCORD_TOKEN" >> ~/red-install.log
    echo "Replace DISCORD_TOKEN in /opt/redbot/.env with a valid Discord bot token." >> ~/red-install.log
fi
cat <<EOF >/opt/redbot/.env
DISCORD_TOKEN=$DISCORD_TOKEN
EOF
$STD chown reduser:reduser /opt/redbot/.env
$STD chmod 600 /opt/redbot/.env
# Run redbot-setup non-interactively
su - reduser -c "echo -e 'redbot\n\n\n\n$DISCORD_TOKEN\n' | /usr/bin/python3 -m redbot_setup" | tee -a ~/red-install.log
msg_ok "Configured Red Discord Bot"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/redbot.service
[Unit]
Description=%i Red Discord Bot
After=multi-user.target
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 -O -m redbot %i --no-prompt
User=reduser
Group=reduser
Type=idle
Restart=on-abnormal
RestartSec=15
RestartForceExitStatus=1
RestartForceExitStatus=26
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable redbot
$STD systemctl start redbot
msg_ok "Service Created"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
