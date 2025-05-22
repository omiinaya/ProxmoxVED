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
var_fuse="${var_fuse:-1}"
var_tun="${var_tun:-1}"
var_nvpass="${var_nvpass:-1}"

header_info "$APP"
variables
color
catch_errors

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

function nvidia_lxc_passthrough() {
    local ctid="$1" minor="$2"
    local conf="/etc/pve/lxc/${ctid}.conf"

    # List of NVIDIA drivers to check for major numbers
    local NVIDIA_DRIVERS="nvidia nvidia-uvm nvidia-modeset nvidia-drm nvidia-caps"

    # Dynamically get major numbers for present drivers from /proc/devices
    local devnums=()
    for DRIVER in $NVIDIA_DRIVERS; do
        local MAJOR
        MAJOR=$(grep "^[0-9]\+ $DRIVER$" /proc/devices | awk '{print $1}')
        if [ -n "$MAJOR" ]; then
            devnums+=("$MAJOR")
            echo "lxc.cgroup2.devices.allow: c $MAJOR:* rwm" >>"$conf"
        fi
    done

    # List of NVIDIA device files to check for mounting
    local NVIDIA_DEVICES=(
        "/dev/nvidia${minor}:none:bind,optional,create=file"
        "/dev/nvidiactl:none:bind,optional,create=file"
        "/dev/nvidia-uvm:none:bind,optional,create=file"
        "/dev/nvidia-uvm-tools:none:bind,optional,create=file"
        "/dev/nvidia-modeset:none:bind,optional,create=file"
        "/dev/nvidia-caps/nvidia-cap1:none:bind,optional,create=file"
        "/dev/nvidia-caps/nvidia-cap2:none:bind,optional,create=file"
        "/dev/fb0:none:bind,optional,create=file"
        "/dev/dri:none:bind,optional,create=dir"
        "/dev/dri/renderD128:none:bind,optional,create=file"
    )

    # Dynamically add mount entries for existing devices
    for DEVICE_ENTRY in "${NVIDIA_DEVICES[@]}"; do
        # Split the entry into device path and mount options
        local DEVICE MOUNT_SRC MOUNT_OPTS
        DEVICE=$(echo "$DEVICE_ENTRY" | cut -d':' -f1)
        MOUNT_SRC=$(echo "$DEVICE_ENTRY" | cut -d':' -f2)
        MOUNT_OPTS=$(echo "$DEVICE_ENTRY" | cut -d':' -f3)
        if [ -e "$DEVICE" ]; then
            echo "lxc.mount.entry: $DEVICE $MOUNT_SRC $MOUNT_OPTS" >>"$conf"
        fi
    done

    msg ok "Installed NVIDIA GPU tools in $ctid"
}

nvidia_lxc_passthrough

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"

read -p "Remove this Container? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    pct stop "$CTID"
    pct destroy "$CTID"
    msg_ok "Removed this script"
else
    msg_warn "Did not remove this script"
fi
