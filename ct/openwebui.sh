#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: havardthom
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openwebui.com/

APP="Open WebUI"
var_tags="${var_tags:-ai;interface}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-25}"
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
  if [[ ! -d /opt/open-webui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [ -x "/usr/bin/ollama" ]; then
    msg_info "Updating Ollama"
    OLLAMA_VERSION=$(ollama -v | awk '{print $NF}')
    RELEASE=$(curl -s https://api.github.com/repos/ollama/ollama/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
    if [ "$OLLAMA_VERSION" != "$RELEASE" ]; then
      curl -fsSLO https://ollama.com/download/ollama-linux-amd64.tgz
      tar -C /usr -xzf ollama-linux-amd64.tgz
      rm -rf ollama-linux-amd64.tgz
      msg_ok "Ollama updated to version $RELEASE"
    else
      msg_ok "Ollama is already up to date."
    fi
  fi

  msg_info "Updating ${APP} (Patience)"
  systemctl stop open-webui.service
  mkdir -p /opt/openwebui-backup
  cp -rf /opt/openwebui/backend/data /opt/openwebui-backup
  cp /opt/openwebui/.env /opt
  rm -rf /opt/openwebui
  fetch_and_deploy_gh_release "open-webui/open-webui"
  cd /opt/openwebui
  $STD npm install
  export NODE_OPTIONS="--max-old-space-size=3584"
  sed -i "s/git rev-parse HEAD/openssl rand -hex 20/g" /opt/openwebui/svelte.config.js
  $STD npm run build
  cd ./backend
  $STD pip install -r requirements.txt -U
  cp -rf /opt/openwebui-backup/* /opt/openwebui/backend
  mv /opt/.env /opt/openwebui/
  systemctl start open-webui.service
  msg_ok "Updated Successfully"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
