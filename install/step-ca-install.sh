#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/smallstep/certificates

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb822_repo \
  "smallstep" \
  "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
  "https://packages.smallstep.com/stable/debian" \
  "debs" \
  "main"

msg_info "Installing step-ca and step-cli"
$STD apt install -y step-ca step-cli
msg_ok "Installed step-ca and step-cli"

msg_info "Define smallstep environment variables"
STEPHOME="/root/.step"
$STD export STEPPATH=/etc/step-ca
$STD export STEPHOME=$STEPHOME
msg_ok "Defined smallstep environment variables"

msg_info "Add smallstep environment variables to /etc/profile"
$STD sed  -i '1i export STEPPATH=/etc/step-ca' /etc/profile
$STD sed  -i '1i export STEPHOME=/root/.step' /etc/profile
msg_ok "Added smallstep environment variables to /etc/profile"

msg_info "Authorize step-ca binary with low port-binding capabilities"
$STD setcap CAP_NET_BIND_SERVICE=+eip $(which step-ca)
msg_ok "Authorized low port-binding capabilities"

msg_info "Add a smallstep CA service user - Will only be used by systemd to manage the CA"
$STD useradd --user-group --system --home $(step path) --shell /bin/false step
msg_ok "Created smallstep CA service user"

#
# Quick & Dirty step-ca init options - to be improved via whiptail
#
DeploymentType="standalone"
FQDN=$(hostname -f)
DomainName=$(hostname -d)
IP=$(hostname -I | awk '{print $1}')
LISTENER=":443"
PKIName="MyHomePKI"
PKIProvisioner="pki@$DomainName"
AcmeProvisioner="acme@$DomainName"
X509MinDur="48h"
X509MaxDur="87600h"
X509DefaultDur="168h"

msg_info "Initializing step-ca"
EncryptionPwdDir="$(step path)/encryption"
PwdFile="$EncryptionPwdDir/ca.pwd"
ProvisionerPwdFile="$EncryptionPwdDir/provisioner.pwd"

$STD mkdir -p "$EncryptionPwdDir"

$STD gpg --gen-random --armor 2 32 >"$PwdFile"
$STD gpg --gen-random --armor 2 32 >"$ProvisionerPwdFile"

$STD step ca init \
  --deployment-type=$DeploymentType \
  --ssh \
  --name=$PKIName \
  --dns="$FQDN" \
  --dns="$IP" \
  --address=$LISTENER \
  --provisioner="$PKIProvisioner" \
  --password-file="$PwdFile" \
  --provisioner-password-file="$ProvisionerPwdFile"

echo
echo "Make a note of the root fingerprint!"
echo "You'll need it in future steps to establish trust with your CA from other environments or hosts."
echo

$STD ln -s "$PwdFile" "$(step path)/password.txt"

$STD chown -R step:step $(step path)
$STD chmod -R 700 $(step path)

msg_ok "Initialized step-ca"

msg_info "Add ACME provisioner"
$STD step ca provisioner add "$AcmeProvisioner" --type ACME --admin-name "$AcmeProvisioner"
msg_ok "Added ACME provisioner"

msg_info "Update provisioner configurations"
$STD step ca provisioner update "$PKIProvisioner" \
   --x509-min-dur=$X509MinDur \
   --x509-max-dur=$X509MaxDur \
   --x509-default-dur=$X509DefaultDur \
   --allow-renewal-after-expiry

$STD step ca provisioner update "$AcmeProvisioner" \
   --x509-min-dur=$X509MinDur \
   --x509-max-dur=$X509MaxDur \
   --x509-default-dur=$X509DefaultDur \
   --allow-renewal-after-expiry
msg_ok "Updated provisioner configurations"

msg_info "Start step-ca as a Daemon"
ServiceFileGitHUB="https://raw.githubusercontent.com/smallstep/certificates/refs/heads/master/systemd/step-ca.service"
$STD curl -fsSL $ServiceFileGitHUB >/etc/systemd/system/step-ca.service
$STD systemctl enable -q --now step-ca
msg_ok "Started step-ca as a Daemon"

msg_info "Install root CA certificate into system's default trust store"
$STD step certificate install --all $(step path)/certs/root_ca.crt
$STD update-ca-certificates
msg_ok "Installed root CA certificate into system's default trust store"

msg_info "Install step-batcher to export step-ca badger database"
StepBadgerGitHUB="https://github.com/lukasz-lobocki/step-badger/releases/latest/download"
StepBadgerArchive="step-badger_Linux_x86_64.tar.gz"
StepBadgerDir="$STEPHOME/step-badger"
StepBadgerExe="$StepBadgerDir/step-badger"
StepBadgerX509Certs="$STEPHOME/step-badger-x509Certs.sh"
StepBadgerSshCerts="$STEPHOME/step-badger-sshCerts.sh"

$STD mkdir -p $StepBadgerDir
$STD curl -fsSL "$StepBadgerGitHUB/$StepBadgerArchive" >$StepBadgerDir/$StepBadgerArchive
$STD tar -xf $StepBadgerDir/$StepBadgerArchive -C $StepBadgerDir

$STD chmod 700 $StepBadgerDir
$STD chmod 400 $StepBadgerDir/*
$STD chmod 755 $StepBadgerExe

$STD cp $StepBadgerExe /usr/local/bin/

$STD mkdir --parents "$STEPHOME/db-copy/"
$STD mkdir --parents "$STEPHOME/certs/ca/"
$STD mkdir --parents "$STEPHOME/certs/ssh/"
$STD mkdir --parents "$STEPHOME/certs/x509/"

$STD cat <<'EOF' >$StepBadgerX509Certs
#!/usr/bin/env bash
#
# See: https://github.com/lukasz-lobocki/step-badger
#

cp --recursive --force "$(step path)/db/"* "$STEPHOME/db-copy/"
cp --recursive --force "$(step path)/certs/"* "$STEPHOME/certs/ca/"

step-badger x509Certs "$STEPHOME/db-copy" \
        --dnsnames \
        --emailaddresses \
        --ipaddresses \
        --uris \
        --issuer \
        --crl \
        --provisioner \
        --algorithm
EOF
$STD cat <<'EOF' >$StepBadgerSshCerts
#!/usr/bin/env bash
#
# See: https://github.com/lukasz-lobocki/step-badger
#

cp --recursive --force "$(step path)/db/"* "$STEPHOME/db-copy/"
cp --recursive --force "$(step path)/certs/"* "$STEPHOME/certs/ca/"

step-badger sshCerts "$STEPHOME/db-copy" \
        --algorithm
EOF
$STD chmod 700 $StepBadgerX509Certs
$STD chmod 700 $StepBadgerSshCerts
msg_ok "Installed step-batcher to export step-ca badger database"

msg_info "Install step-ca helper scripts"
StepRequest="$STEPHOME/step-ca-request.sh"
StepRevoke="$STEPHOME/step-ca-revoke.sh"
$STD cat <<'EOF' >$StepRequest
#!/usr/bin/env bash
#
StepCertDir="$STEPHOME/certs/x509"

HOST="brw4cd5770e36b4"
IP="192.168.178.136"
DOMAIN="fritz.box"
FQDN=$HOST.$DOMAIN
VALID_TO="2034-01-31T00:00:00Z"
PROVISIONER="pki@fritz.box"

step ca certificate $FQDN $StepCertDir/$FQDN.crt $StepCertDir/$FQDN.key \
  --provisioner=$PROVISIONER \
  --not-after=$VALID_TO \
  --san $FQDN \
  --san $HOST \
  --san $IP

step certificate inspect $StepCertDir/$FQDN.crt
EOF
$STD cat <<'EOF' >$StepRevoke
#!/usr/bin/env bash
#
# step ca revoke <serialnumber>
#
step ca revoke
EOF
$STD chmod 700 $StepRequest
$STD chmod 700 $StepRevoke
msg_ok "Installed step-ca helper scripts"

motd_ssh
customize
cleanup_lxc
