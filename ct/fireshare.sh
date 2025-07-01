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

  msg_info "Updating ${APP} LXC"

  RELEASE_TAG=$(curl -s https://api.github.com/repos/ShaneIsrael/fireshare/releases/latest | jq -r .tag_name)
  CURRENT_VERSION=""
  if [ -f "/opt/${APP}_version.txt" ]; then
    CURRENT_VERSION=$(cat "/opt/${APP}_version.txt")
  fi

  if [[ "${RELEASE_TAG}" != "${CURRENT_VERSION}" ]]; then
    msg_info "Updating ${APP} to ${RELEASE_TAG}"
    systemctl stop fireshare

    cd /opt
    rm -rf fireshare

    curl -fsSL "https://github.com/ShaneIsrael/fireshare/archive/refs/tags/${RELEASE_TAG}.tar.gz" | tar -xzf -
    RELEASE_VERSION=$(echo "$RELEASE_TAG" | sed 's/^v//')
    mv "fireshare-${RELEASE_VERSION}" fireshare

    cd /opt/fireshare
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r app/server/requirements.txt
    pip install gunicorn
    cd app/server && python3 setup.py install && cd ../..
    flask db upgrade
    deactivate

    npm --prefix app/client install
    npm --prefix app/client run build

    # Correct the start script
    cat <<EOF >/opt/fireshare/start.sh
#!/usr/bin/env bash
source /opt/fireshare/.venv/bin/activate
gunicorn --workers 4 -b 0.0.0.0:8080 "app.server:create_app()"
EOF
    chmod +x /opt/fireshare/start.sh

    systemctl start fireshare
    echo "${RELEASE_TAG}" >"/opt/${APP}_version.txt"
    msg_ok "Updated ${APP} to ${RELEASE_TAG}"
  else
    msg_ok "No update required. ${APP} is already at ${CURRENT_VERSION}"
  fi

  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated ${APP} LXC"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
