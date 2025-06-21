#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing2/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kevinanielsen/go-fast-cdn

APP="Go Fast CDN"
var_tags="${var_tags:-cdn,storage,networking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-10}"
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
  if [[ ! -f /opt/go-fast-cdn/go-fast-cdn ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"

  RELEASE=$(curl -fsSL https://api.github.com/repos/kevinanielsen/go-fast-cdn/releases/latest | jq -r .tag_name)

  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Updating ${APP} to ${RELEASE}"

    # Stop service
    systemctl stop go-fast-cdn || true

    # Backup current installation
    cp /opt/go-fast-cdn/go-fast-cdn /opt/go-fast-cdn/go-fast-cdn.backup

    # Download and extract new version
    cd /tmp
    curl -fsSL -o "go-fast-cdn_${RELEASE}_linux_amd64.zip" "https://github.com/kevinanielsen/go-fast-cdn/releases/download/${RELEASE}/go-fast-cdn_${RELEASE}_linux_amd64.zip"
    unzip -o "go-fast-cdn_${RELEASE}_linux_amd64.zip"

    # Update binary
    mv go-fast-cdn /opt/go-fast-cdn/
    chmod +x /opt/go-fast-cdn/go-fast-cdn

    # Start service
    systemctl start go-fast-cdn || true

    # Cleanup
    rm -f "/tmp/go-fast-cdn_${RELEASE}_linux_amd64.zip"
    rm -f "/opt/go-fast-cdn/go-fast-cdn.backup"

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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
