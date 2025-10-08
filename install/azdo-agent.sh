#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Name:         Azure DevOps Agent LXC Installer
# Description:  Deploy a self-hosted Azure DevOps Linux Agent in an LXC container
# Based on:     https://github.com/community-scripts/ProxmoxVE (Tteck's helpers)
# ----------------------------------------------------------------------------------

set -euo pipefail
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")

REPO="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
source <(curl -s ${REPO}/misc/build.func)

# --- Define defaults ---
APP="azdo-agent"
var_disk="10"
var_cpu="2"
var_ram="4096"
var_os="ubuntu"
var_version="22.04"
var_features="nesting=1,keyctl=1,fuse=1"

# --- Prompt user ---
header_info "Azure DevOps Agent LXC Installer"

read -r -p "Enter Azure DevOps organization URL (e.g. https://dev.azure.com/YourOrg): " AZDO_URL
read -r -p "Enter Personal Access Token (PAT): " AZDO_PAT
read -r -p "Enter Agent Pool name (default: Default): " AZDO_POOL
AZDO_POOL=${AZDO_POOL:-Default}
read -r -p "Enter Agent Name (default: lxc-agent-1): " AZDO_NAME
AZDO_NAME=${AZDO_NAME:-lxc-agent-1}

# --- Create LXC container ---
build_container

# --- Inside container install function ---
post_install() {
  header_info "Installing Azure DevOps Agent..."

  apt-get update && apt-get install -y curl git jq unzip ca-certificates apt-transport-https sudo

  useradd -m -s /bin/bash azdo
  echo "azdo ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/azdo

  su - azdo <<'EOF'
cd ~
AGENT_VERSION=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r .tag_name | tr -d 'v')
wget https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz
mkdir myagent && cd myagent
tar zxvf ../vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz

./config.sh --unattended \
  --url "${AZDO_URL}" \
  --auth pat \
  --token "${AZDO_PAT}" \
  --pool "${AZDO_POOL}" \
  --agent "${AZDO_NAME}" \
  --acceptTeeEula \
  --replace

sudo ./svc.sh install
sudo ./svc.sh start
EOF

  echo -e "${GN}✅ Azure DevOps Agent installation complete!${CL}"
  echo -e "Agent: ${BL}${AZDO_NAME}${CL}"
  echo -e "URL:   ${BL}${AZDO_URL}${CL}"
  echo -e "Pool:  ${BL}${AZDO_POOL}${CL}"
}

post_install
