#!/usr/bin/env bash
source <(curl -s https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Adapted for Shlink
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/shlinkio/shlink

APP="Shlink"
var_tags="${var_tags:-url shortener}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/shlink ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating $APP LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    # Rename existing directory
    if [[ -d /opt/shlink-old ]]; then
        $STD rm -rf /opt/shlink-old
    fi
    $STD mv /opt/shlink /opt/shlink-old
    # Download and extract new version
    RELEASE=$(curl -fsSL https://api.github.com/repos/shlinkio/shlink/releases/latest | jq -r .tag_name | sed 's/^v//')
    curl -fsSL -o "/tmp/shlink-${RELEASE}-php8.4-dist.zip" "https://github.com/shlinkio/shlink/releases/download/v${RELEASE}/shlink-${RELEASE}-php8.4-dist.zip" | tee -a ~/shlink-install.log
    $STD unzip -q "/tmp/shlink-${RELEASE}-php8.4-dist.zip" -d /opt/shlink
    $STD chown -R shlink:shlink /opt/shlink
    $STD chmod -R u+w /opt/shlink/data
    # Run update installer
    su - shlink -c "cd /opt/shlink && php vendor/bin/shlink-installer update --import-from /opt/shlink-old" | tee -a ~/shlink-install.log
    # Clean up
    $STD rm -rf /opt/shlink-old
    $STD rm -f "/tmp/shlink-${RELEASE}-php8.4-dist.zip"
    $STD systemctl restart shlink
    msg_ok "Updated $APP LXC"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the web interface at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
