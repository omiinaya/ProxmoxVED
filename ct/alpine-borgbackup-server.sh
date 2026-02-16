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

  CHOICE=$(msg_menu "BorgBackup Server Update Options" \
    "1" "Update BorgBackup Server" \
    "2" "Reset SSH Access" \
    "3" "Enable password authentication for backup user (not recommended, use SSH key instead)" \
    "4" "Disable password authentication for backup user (recommended for security, use SSH key)")

  case $CHOICE in
  1)
    msg_info "Updating $APP LXC"
    $STD apk -U upgrade
    msg_ok "Updated $APP LXC successfully!"
    ;;
  2)
    if [[ "${PHS_SILENT:-0}" == "1" ]]; then
      msg_warn "Reset SSH Public key requires interactive mode, skipping."
      exit
    fi

    msg_info "Setting up SSH Public Key for backup user"

    # Get SSH public key from user
    msg_info "Please paste your SSH public key (e.g., ssh-rsa AAAAB3... user@host): \n"
    read -p "Key: " SSH_PUBLIC_KEY
    echo

    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
      msg_error "No SSH public key provided!"
      exit 1
    fi

    # Validate that it looks like an SSH public key
    if [[ ! "$SSH_PUBLIC_KEY" =~ ^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-) ]]; then
      msg_error "Invalid SSH public key format!"
      exit 1
    fi

    # Set up SSH directory and authorized_keys file
    msg_info "Setting up SSH access"
    mkdir -p /home/backup/.ssh
    echo "$SSH_PUBLIC_KEY" > /home/backup/.ssh/authorized_keys

    # Set correct permissions
    chown -R backup:backup /home/backup/.ssh
    chmod 700 /home/backup/.ssh
    chmod 600 /home/backup/.ssh/authorized_keys

    msg_ok "SSH access configured for backup user"
    ;;
  3)
    if [[ "${PHS_SILENT:-0}" == "1" ]]; then
      msg_warn "Enabling password authentication requires interactive mode, skipping."
      exit
    fi

    msg_info "Enabling password authentication for backup user"
    msg_warn "Password authentication is less secure than using SSH keys. Consider using SSH keys instead."
    passwd backup
    sed -i 's/^#*\s*PasswordAuthentication\s\+\(yes\|no\)/PasswordAuthentication yes/' /etc/ssh/sshd_config
    rc-service sshd restart
    msg_ok "Password authentication enabled for backup user"
    ;;
  4)
    msg_info "Disabling password authentication for backup user"
    sed -i 's/^#*\s*PasswordAuthentication\s\+\(yes\|no\)/PasswordAuthentication no/' /etc/ssh/sshd_config
    rc-service sshd restart
    msg_ok "Password authentication disabled for backup user"
    ;;
  esac

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
