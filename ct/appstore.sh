#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.debian.org/

APP="AppStore"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

interface=$(ip route | grep default | awk '{print $5}')
var_host_ip=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d'/' -f1)

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /var ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating $APP LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated $APP LXC"
    exit
}

start
build_container

msg_info "Configuring SSH access for container"
AUTH_KEYS="/root/.ssh/authorized_keys"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
PUBLIC_KEY=$(pct exec $CTID -- cat /root/.ssh/id_rsa.pub 2>/dev/null)
echo "$PUBLIC_KEY" >>"$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
msg_ok "Added container's public key to host's authorized_keys"

msg_info "Rebooting"
pct stop $CTID
pct start $CTID
msg_ok "Rebooted"

msg_info "Installing Node"
nvm install 22
nvm use 22
node -v
msg_ok "Installed Node"

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
