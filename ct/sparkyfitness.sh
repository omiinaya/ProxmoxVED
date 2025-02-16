#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/tomfrenzel/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tom Frenzel
# License: MIT | https://github.com/tomfrenzel/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

APP="SparkyFitness"
var_tags="${var_tags:-health;fitness}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/sparkyfitness ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="20" setup_nodejs

  if check_for_gh_release "sparkyfitness" "CodeWithCJ/SparkyFitness"; then
    msg_info "Stopping Services"
    systemctl stop sparkyfitness-server
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "sparkyfitness" "CodeWithCJ/SparkyFitness" "tarball"

    msg_info "Updating Sparky Fitness Backend"
    cd /opt/sparkyfitness/SparkyFitnessServer
    $STD npm install
    msg_ok "Updated Sparky Fitness Backend"

    msg_info "Updating Sparky Fitness Frontend"
    cd /opt/sparkyfitness/SparkyFitnessFrontend
    $STD npm install
    $STD npm run build
    rm -rf /var/www/sparkyfitness/*
    cp -a /opt/sparkyfitness/SparkyFitnessFrontend/dist/. /var/www/sparkyfitness/
    msg_ok "Updated Sparky Fitness Frontend"

    chown -R sparkyfitness:sparkyfitness /opt/sparkyfitness

    msg_info "Starting Services"
    $STD systemctl daemon-reload
    $STD systemctl restart sparkyfitness-server
    $STD systemctl restart nginx
    msg_ok "Started Services"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3004${CL}"
