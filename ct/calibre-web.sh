#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: mikolaj92
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/janeczku/calibre-web

APP="calibre-web"
var_tags="${var_tags:-media;books}" # Max 2 tags, semicolon-separated
var_cpu="${var_cpu:-2}"                         # CPU cores: 1-4 typical
var_ram="${var_ram:-2048}"                      # RAM in MB: 512, 1024, 2048, etc.
var_disk="${var_disk:-8}"                       # Disk in GB: 6, 8, 10, 20 typical
var_os="${var_os:-debian}"                      # OS: debian, ubuntu, alpine
var_version="${var_version:-13}"                # OS Version: 13 (Debian), 24.04 (Ubuntu), 3.21 (Alpine)
var_unprivileged="${var_unprivileged:-1}"       # 1=unprivileged (secure), 0=privileged (for Docker/Podman)

header_info "$APP" # Display app name and setup header
variables          # Initialize build.func variables
color              # Load color variables for output
catch_errors       # Enable error handling with automatic exit on failure

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/calibre-web ]]; then
    msg_error "No Calibre-Web Installation Found!"
    exit
  fi

  if check_for_gh_release "calibre-web" "janeczku/calibre-web"; then

    msg_info "Stopping Service"
    systemctl stop calibre-web
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/calibre-web/app.db /opt/calibre-web/app.db_backup 2>/dev/null
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "calibre-web" "janeczku/calibre-web" "tarball" "latest" "/opt/calibre-web"

    msg_info "Installing Dependencies"
    cd /opt/calibre-web
    $STD pip3 install --no-cache-dir -r requirements.txt
    msg_ok "Installed Dependencies"

    msg_info "Restoring Data"
    cp /opt/calibre-web/app.db_backup /opt/calibre-web/app.db 2>/dev/null
    rm -f /opt/calibre-web/app.db_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start calibre-web
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8083${CL}"
