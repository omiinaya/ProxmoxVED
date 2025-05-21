#!/usr/bin/env bash

# Copyright (c) 2025 community-scripts ORG
# Author: Adapted for Trellis
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/microsoft/TRELLIS

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    build-essential \
    python3 \
    python3-pip \
    python3-dev \
    libgl1-mesa-glx \
    libglib2.0-0
msg_ok "Installed Dependencies"

msg_info "Installing Miniconda"
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
$STD bash miniconda.sh -b -p /opt/miniconda
export PATH="/opt/miniconda/bin:$PATH"
$STD conda init bash
msg_ok "Installed Miniconda"

motd_ssh
customize

msg_info "Cleaning up"
rm -f /miniconda.sh
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
