#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing2/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar (omiinaya)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ShaneIsrael/fireshare

APP="Fireshare"
var_tags="${var_tags:-media,sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/fireshare ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  TAG=$(curl -s https://api.github.com/repos/ShaneIsrael/fireshare/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')
  RELEASE=${TAG#v}
  if [[ "${RELEASE}" != "$(cat /opt/fireshare_version.txt)" ]] || [[ ! -f /opt/fireshare_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop fireshare
    msg_ok "Stopped $APP"

    msg_info "Updating $APP to v${RELEASE}"
    cd /opt
    rm -rf /opt/fireshare
    curl -fsSL "https://github.com/ShaneIsrael/fireshare/archive/refs/tags/${TAG}.tar.gz" | tar -xzf -
    mv fireshare-${RELEASE} fireshare
    cd /opt/fireshare
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    pip install gunicorn
    npm --prefix app/client install
    npm --prefix app/client run build
    flask db upgrade
    deactivate
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start fireshare
    msg_ok "Started $APP"

    echo "${RELEASE}" >/opt/fireshare_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
