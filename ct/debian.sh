#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.debian.org/

APP="Debian"
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

# Automatically get host IP from vmbr0
var_host_ip=$(ip -4 addr show vmbr0 | grep inet | awk '{print $2}' | cut -d'/' -f1)
if [ -z "$var_host_ip" ]; then
    msg_error "Failed to detect host IP on vmbr0! Please ensure vmbr0 is configured."
    exit 1
fi
msg_ok "Detected host IP: $var_host_ip"

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
# Pass host IP to container
export var_host_ip
build_container

msg_ok $CTID

# Ensure container is running
pct start $CTID

# Set up SSH key on host
msg_info "Configuring SSH access for container"
AUTH_KEYS="/root/.ssh/authorized_keys"
# Ensure .ssh directory exists on host
mkdir -p /root/.ssh
chmod 700 /root/.ssh
# Retrieve public key from container using pct exec
PUBLIC_KEY=$(pct exec $CTID -- cat /root/.ssh/id_rsa.pub 2>/dev/null)

# Append public key to authorized_keys without restrictions
echo "$PUBLIC_KEY" >>"$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
msg_ok "Added container's public key to host's authorized_keys"

# Verify SSH connectivity from container
msg_info "Testing SSH connectivity"
if pct exec "$CTID" -- ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$var_host_ip" true >/dev/null 2>&1; then
    msg_ok "SSH access to host configured successfully"
else
    msg_error "Failed to configure SSH access to host"
    exit 1
fi

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
