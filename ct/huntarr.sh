#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: BiluliB
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/plexguide/Huntarr.io

APP="huntarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
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

  if [[ ! -f /opt/${APP}/main.py ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_uv
  RELEASE=$(curl -fsSL https://api.github.com/repos/plexguide/Huntarr.io/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
  if [[ -f /opt/${APP}_version.txt ]] && [[ "${RELEASE}" == "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
    exit
  fi
  msg_info "Stopping $APP"
  systemctl stop ${APP}
  msg_ok "Stopped $APP"

  msg_info "Creating Backup"
  if ls /opt/"${APP}"_backup_*.tar.gz &>/dev/null; then
    rm -f /opt/"${APP}"_backup_*.tar.gz
    msg_info "Removed previous backup"
  fi
  tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /opt/"${APP}"
  msg_ok "Backup Created"

  msg_info "Updating $APP to v${RELEASE}"
  temp_file=$(mktemp)
  curl -fsSL -o "$temp_file" "https://github.com/plexguide/Huntarr.io/archive/refs/tags/${RELEASE}.zip"
  unzip -q -o "$temp_file" -d /tmp
  cp -rf "/tmp/Huntarr.io-${RELEASE}"/* /opt/"${APP}"/

  msg_info "Updating Python dependencies"
  cd /opt/"${APP}" || exit
  if [[ -f "/opt/${APP}/.requirements_checksum" ]]; then
    CURRENT_CHECKSUM=$(md5sum requirements.txt | awk '{print $1}')
    STORED_CHECKSUM=$(cat .requirements_checksum)
    if [[ "$CURRENT_CHECKSUM" != "$STORED_CHECKSUM" ]]; then
      msg_info "Requirements have changed. Performing full upgrade."
      $STD uv pip install -r requirements.txt --python /opt/"${APP}"/venv/bin/python
    else
      msg_info "Requirements unchanged. Verifying installation."
      $STD uv pip install -r requirements.txt --python /opt/"${APP}"/venv/bin/python
    fi
  else
    $STD uv pip install -r requirements.txt --python /opt/"${APP}"/venv/bin/python
  fi
  md5sum requirements.txt | awk '{print $1}' >.requirements_checksum
  msg_ok "Updated Python dependencies"

  msg_info "Starting $APP"
  systemctl start ${APP}
  msg_ok "Started $APP"

  msg_info "Cleaning Up"
  rm -f "$temp_file"
  rm -rf "/tmp/Huntarr.io-${RELEASE}"
  msg_ok "Cleanup Completed"

  echo "${RELEASE}" >/opt/"${APP}"_version.txt
  msg_ok "Updated $APP to v${RELEASE}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9705${CL}"
