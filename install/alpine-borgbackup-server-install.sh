#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Sander Koenders (sanderkoenders)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.borgbackup.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing BorgBackup"
$STD apk add --no-cache borgbackup openssh
$STD rc-update add sshd
$STD rc-service sshd start
msg_ok "Installed BorgBackup"

motd_ssh
customize
cleanup_lxc
