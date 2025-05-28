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
    if [[ ! -d /var ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating $APP LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    RELEASE=$(curl -fsSL https://api.github.com/repos/shlinkio/shlink/releases/latest | jq -r .tag_name | sed 's/^v//')
    curl -fsSL -o "/tmp/shlink-${RELEASE}-php8.4-dist.zip" "https://github.com/shlinkio/shlink/releases/download/v${RELEASE}/shlink-${RELEASE}-php8.4-dist.zip"
    $STD unzip -q -o "/tmp/shlink-${RELEASE}-php8.4-dist.zip" -d /opt/shlink
    $STD chown -R shlink:shlink /opt/shlink
    $STD chmod -R u+w /opt/shlink/data
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
echo -e "${INFO}${YW} Copy the API key from ~/shlink-install.log for API access.${CL}"
echo -e "${INFO}${YW} Configure your domain in the web interface or /opt/shlink/.env.${CL}"
echo -e "${INFO}${YW} Check logs: journalctl -eu shlink${CL}"
echo -e "${INFO}${YW} Check install logs: cat ~/shlink-install.log${CL}"
