#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ShaneIsrael/fireshare

APP="Fireshare"
var_tags="${var_tags:-media,sharing,video}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/fireshare ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"

  RELEASE=$(curl -fsSL https://api.github.com/repos/ShaneIsrael/fireshare/releases/latest | jq -r .tag_name)
  if [[ ! -f "/opt/${APP}_version.txt" ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Updating ${APP} to ${RELEASE}"

    # Stop services
    systemctl stop fireshare-backend
    systemctl stop fireshare-frontend

    # Backup current installation
    cp -r /opt/fireshare /opt/fireshare-backup

    # Download and extract new version
    cd /tmp
    curl -fsSL -o "fireshare-${RELEASE}.tar.gz" "https://github.com/ShaneIsrael/fireshare/archive/refs/tags/${RELEASE}.tar.gz"
    tar -xf "fireshare-${RELEASE}.tar.gz"

    # Update application
    cp -r "fireshare-${RELEASE}"/* /opt/fireshare/
    cd /opt/fireshare

    # Install dependencies and build
    npm install
    cd app/client
    npm install
    npm run build
    cd ../..

    # Start services
    systemctl start fireshare-backend
    systemctl start fireshare-frontend

    # Cleanup
    rm -rf "/tmp/fireshare-${RELEASE}.tar.gz /tmp/fireshare-${RELEASE}"
    rm -rf /opt/fireshare-backup

    echo "${RELEASE}" >"/opt/${APP}_version.txt"
    msg_ok "Updated ${APP} to ${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi

  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated $APP LXC"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
