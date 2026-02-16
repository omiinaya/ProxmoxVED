#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Sander Koenders (sanderkoenders)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.borgbackup.org/

APP="Alpine-BorgBackup-Server"
var_tags="${var_tags:-alpine;backup}"            # Max 2 tags, semicolon-separated
var_cpu="${var_cpu:-2}"                         # CPU cores: 1-4 typical
var_ram="${var_ram:-1024}"                      # RAM in MB: 512, 1024, 2048, etc.
var_disk="${var_disk:-20}"                      # Disk in GB: 6, 8, 10, 20 typical
var_os="${var_os:-alpine}"                      # OS: debian, ubuntu, alpine
var_version="${var_version:-3.23}"              # OS Version: 13 (Debian), 24.04 (Ubuntu), 3.23 (Alpine)
var_unprivileged="${var_unprivileged:-1}"       # 1=unprivileged (secure), 0=privileged (for Docker/Podman)

header_info "$APP" # Display app name and setup header
variables          # Initialize build.func variables
color              # Load color variables for output
catch_errors       # Enable error handling with automatic exit on failure

function update_script() {
  header_info

  if [[ ! -f /usr/bin/borg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"

  msg_ok "Updated successfully!"
  exit 0
}

start
build_container
description

# ============================================================================
# COMPLETION MESSAGE
# ============================================================================
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Connection information:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}ssh backup@${IP}${CL}"
echo -e "${TAB}${VERIFYPW}${YW}To set SSH key, run this script with the 'update' option and select option 2${CL}"
