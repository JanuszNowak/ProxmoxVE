#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Title:        Azure DevOps Agent - LXC Installer for Proxmox VE
# Description:  Deploys an Ubuntu LXC container and installs Azure Pipelines Agent
# Author:       Janusz Nowak (based on community-scripts/ProxmoxVE templates)
# ----------------------------------------------------------------------------------

set -Eeuo pipefail
shopt -s expand_aliases

# --- Predefine required variables for build.func ---
export BRG="vmbr0"                           # Default Proxmox network bridge
export RANDOM_UUID=$(cat /proc/sys/kernel/random/uuid)
export DIAGNOSTICS=false                     # Disable build diagnostics
export NSAPP="Azure DevOps Agent"            # App name for log headers
export MAC=""                                # placeholder, set later

# --- Load community build functions ---
REPO="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
source <(curl -fsSL ${REPO}/misc/build.func)

# --- Container configuration ---
APP="azdo-agent"
var_cpu="2"
var_ram="4096"
var_disk="10"
var_os="ubuntu"
var_version="22.04"
var_features="nesting=1,keyctl=1,fuse=1"
var_unprivileged="1"

# --- Build container ---
build_container

# --- Generate MAC address based on CTID ---
if [[ -n "${CTID:-}" ]]; then
  # Get CTID in 4-digit hexadecimal (e.g., 2005 → 0x07D5)
  HEXID=$(printf '%04x' "$CTID")
  # Use last four hex digits as final two MAC bytes
  export MAC="00:00:00:00:${HEXID:0:2}:${HEXID:2:2}"
  pct set "$CTID" -net0 "name=eth0,bridge=${BRG},hwaddr=${MAC},ip=dhcp"
  msg_info "Assigned MAC address based on CTID ${CTID}: ${MAC}"
else
  msg_warn "CTID not defined; skipping MAC assignment."
fi

# --- Post-create installation inside container ---
container_exec() {
  cat <<'INCONTAINER' | bash -e
    set -Eeuo pipefail
    apt-get update
    apt-get install -y curl jq unzip apt-transport-https ca-certificates gnupg lsb-release sudo

    # Create user for the agent
    useradd -m -s /bin/bash azdo || true
    cd /home/azdo

    # Download latest Azure Pipelines agent
    echo "Fetching latest Azure Pipelines agent version..."
    AGENT_VERSION=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r '.tag_name')
    AGENT_VERSION_CLEAN=${AGENT_VERSION#v}

    echo "Downloading agent version $AGENT_VERSION_CLEAN..."
    curl -fsSL -o agent.tar.gz "https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION_CLEAN}/vsts-agent-linux-x64-${AGENT_VERSION_CLEAN}.tar.gz"
    tar zxvf agent.tar.gz
    chown -R azdo:azdo /home/azdo

    echo "-------------------------------------------------------------"
    echo "✅ Azure DevOps agent files installed at /home/azdo"
    echo "-------------------------------------------------------------"
    echo "To configure this agent, connect into the container and run:"
    echo "  sudo -u azdo ./config.sh"
    echo "Then start the service with:"
    echo "  sudo -u azdo ./svc.sh install"
    echo "  sudo -u azdo ./svc.sh start"
    echo "-------------------------------------------------------------"
INCONTAINER
}

# --- Run post-create steps ---
post_create container_exec

# --- Summary ---
msg_ok "Azure DevOps LXC Agent Container setup complete!"
msg_info "Connect via: pct enter ${CTID}"
