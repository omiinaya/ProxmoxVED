#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y openssh-client
#$STD apt-get install -y gnup
msg_ok "Installed Dependencies"

msg_info "Generating SSH key pair"
# Generate SSH key pair for root user
SSH_KEY_PATH="/root/.ssh/id_rsa"
$STD ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "container-ssh-key"
msg_ok "Generated SSH key pair"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
