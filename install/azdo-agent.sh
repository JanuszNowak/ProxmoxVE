#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Name: azdo-agent.sh
# Description: Install Azure DevOps Self-Hosted Agent in an LXC container on Proxmox
# Based on: https://github.com/community-scripts/ProxmoxVE
# ----------------------------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"' ERR

# Load helper functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# ----------------------------------------------------------------------------------
# Script Metadata
# ----------------------------------------------------------------------------------
APP="azdo-agent"
var_os="debian"
var_version="12"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_network="1"
var_user="azdo"
var_pass="Azdo123!"
var_ctid_next
default_ctid

# ----------------------------------------------------------------------------------
# Load Variable Dialogs (enables whiptail prompts)
# ----------------------------------------------------------------------------------
variables

# ----------------------------------------------------------------------------------
# Default MAC (if user skipped input)
# ----------------------------------------------------------------------------------
if [[ -z "${MAC:-}" ]]; then
  printf -v MAC "00:00:00:00:%02X:%02X" $((CTID/256)) $((CTID%256))
fi

# ----------------------------------------------------------------------------------
# Create Container
# ----------------------------------------------------------------------------------
msg_info "Creating LXC container..."
pct create "$CTID" "$var_os:$var_version" \
  -arch amd64 \
  -hostname "$APP" \
  -net0 "name=eth0,bridge=${BRG:-vmbr0},ip=${NET:-dhcp},tag=${TAG:-},gw=${GW:-},firewall=1,macaddr=${MAC}" \
  -cores "$var_cpu" \
  -memory "$var_ram" \
  -rootfs "${STORAGE:-local-lvm}:${var_disk}" \
  -unprivileged 1 \
  -features nesting=1 \
  -password "$var_pass"
msg_ok "Container $CTID created with MAC $MAC"

# ----------------------------------------------------------------------------------
# Start Container
# ----------------------------------------------------------------------------------
pct start "$CTID"
sleep 5

# ----------------------------------------------------------------------------------
# Inside the Container: Install Azure DevOps Agent
# ----------------------------------------------------------------------------------
msg_info "Installing Azure DevOps Agent inside container..."

pct exec "$CTID" -- bash -c "
  set -e
  apt-get update -y
  apt-get install -y curl tar jq git libicu-dev
  useradd -m $var_user || true
  cd /home/$var_user
  AGENT_VERSION=\$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r '.tag_name' | sed 's/v//')
  curl -LsO https://vstsagentpackage.azureedge.net/agent/\$AGENT_VERSION/vsts-agent-linux-x64-\$AGENT_VERSION.tar.gz
  tar zxvf vsts-agent-linux-x64-\$AGENT_VERSION.tar.gz
  chown -R $var_user:$var_user /home/$var_user
"

msg_ok "Azure DevOps Agent downloaded and unpacked."

# ----------------------------------------------------------------------------------
# Instructions to finalize setup
# ----------------------------------------------------------------------------------
msg_info "To finalize agent setup, run inside container:"
echo
echo "pct exec $CTID -- bash"
echo "su - $var_user"
echo "./config.sh --url https://dev.azure.com/<ORG> --auth pat --token <TOKEN> --pool <POOLNAME> --agent $(hostname)"
echo "sudo ./svc.sh install"
echo "sudo ./svc.sh start"
echo
msg_ok "Azure DevOps agent ready to configure."
