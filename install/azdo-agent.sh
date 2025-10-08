#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Title:        Azure DevOps Agent - LXC Installer for Proxmox VE
# Description:  Deploys an Ubuntu LXC container and installs Azure Pipelines Agent
# Author:       Janusz Nowak (based on Tteck ProxmoxVE templates)
# ----------------------------------------------------------------------------------

set -Eeuo pipefail
shopt -s expand_aliases

# --- Load build functions ---
REPO="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
source <(curl -fsSL ${REPO}/misc/build.func)

# --- Required Variables for build.func ---
BRG="vmbr0"
MAC=""
RANDOM_UUID=$(cat /proc/sys/kernel/random/uuid)
DIAGNOSTICS=false
NSAPP="Azure DevOps Agent"

# --- Container Configuration ---
APP="azdo-agent"
var_cpu="2"
var_ram="4096"
var_disk="10"
var_os="ubuntu"
var_version="22.04"
var_features="nesting=1,keyctl=1,fuse=1"
var_unprivileged="1"

# --- Build Container ---
build_container

# --- Inside Container Installation ---
container_exec() {
  cat <<'INCONTAINER' | bash -e
    set -Eeuo pipefail
    apt-get update
    apt-get install -y curl jq unzip apt-transport-https ca-certificates gnupg lsb-release

    # Create azdo user
    useradd -m -s /bin/bash azdo || true
    cd /home/azdo

    # Download latest Azure Pipelines agent
    AGENT_VERSION=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r '.tag_name')
    curl -fsSL -o agent.tar.gz "https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION:1}/vsts-agent-linux-x64-${AGENT_VERSION:1}.tar.gz"
    tar zxvf agent.tar.gz
    chown -R azdo:azdo /home/azdo

    echo "-------------------------------------------------------------"
    echo "✅ Azure DevOps agent files installed at /home/azdo"
    echo "-------------------------------------------------------------"
    echo "To configure this agent, connect into container and run:"
    echo "  sudo -u azdo ./config.sh"
    echo "Then start the agent with:"
    echo "  sudo -u azdo ./svc.sh install"
    echo "  sudo -u azdo ./svc.sh start"
    echo "-------------------------------------------------------------"
INCONTAINER
}

post_create container_exec

# --- Display Info ---
msg_ok "Azure DevOps LXC Agent Container setup complete!"
msg_info "Connect via: pct enter $CTID"
