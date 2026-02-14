#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.seerr.dev/

APP="Jellyseerr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
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

  if [[ ! -d /opt/seerr && ! -d /opt/jellyseerr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ -f /etc/systemd/system/jellyseerr.service ]]; then
    msg_info "Stopping Jellyseerr"
    $STD systemctl stop jellyseerr || true
    $STD systemctl disable jellyseerr || true
    [ -f /etc/systemd/system/jellyseerr.service ] && rm -f /etc/systemd/system/jellyseerr.service
    msg_ok "Stopped Jellyseerr"
    
    msg_info "Creating Backup"
    tar -czf /opt/jellyseerr_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C /opt/jellyseerr
    msg_ok "Created Backup"

    msg_info "Migrating Jellyseerr to seerr"
    [ -d /opt/jellyseerr ] && mv /opt/jellyseerr /opt/seerr
    [ -d /etc/jellyseerr ] && mv /etc/jellyseerr /etc/seerr
    cat <<EOF >/etc/systemd/system/seerr.service
[Unit]
Description=Seerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/seerr/seerr.conf
Environment=NODE_ENV=production
Type=exec
Restart=on-failure
WorkingDirectory=/opt/seerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q --now seerr
    msg_info "Migrated Jellyserr to Seerr"
  fi

  if check_for_gh_release "seerr" "seerr-team/seerr"; then
    msg_info "Stopping Service"
    systemctl stop seerr
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    cp -a /opt/seerr/config /opt/seerr_backup
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "seerr" "seerr-team/seerr" "tarball"  

    msg_info "Updating PNPM Version"
    cd /opt/seerr 
    pnpm_current=$(pnpm --version 2>/dev/null)
    pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/seerr/package.json)
    if [ -z "$pnpm_current" ]; then
      msg_error "pnpm not found. Installing version $pnpm_desired..."
      NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs
    elif ! node -e "const semver = require('semver'); process.exit(semver.satisfies('$pnpm_current', '$pnpm_desired') ? 0 : 1)"; then
      msg_error "Updating pnpm from version $pnpm_current to $pnpm_desired..."
      NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs
    else
    msg_ok "pnpm is already installed and satisfies version $pnpm_desired."
    fi
    msg_info "Updated PNPM Version"

    msg_info "Updating Seerr"
    rm -rf dist .next node_modules
    export CYPRESS_INSTALL_BINARY=0
    $STD pnpm install --frozen-lockfile
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD pnpm build
    msg_ok "Updated Seerr"

    msg_info "Restoring Backup"
    rm -rf /opt/seerr/config
    mv /opt/seerr_backup /opt/seerr/config
    msg_ok "Restored Backup"

    msg_info "Starting Service"
    systemctl start seerr
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5055${CL}"
