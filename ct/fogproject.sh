#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://fogproject.org/

APP="FOGProject"
var_tags="${var_tags:-imaging}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

# Check for NFS server support
if [[ "${var_unprivileged}" == "1" ]]; then
  msg_warn "Unprivileged LXC detected. FOGProject requires NFS server support, which is usually only available in privileged containers."
  if ! grep -q nfs /proc/filesystems; then
    msg_warn "NFS server kernel module not available. FOG imaging will fail unless NFS is enabled on the host and container."
  fi
fi

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/fogproject-stable ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  cd /opt/fogproject-stable/bin
  $STD sudo ./installfog.sh -y
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the FOG web UI at: http://${IP}/fog/ ${CL}"
