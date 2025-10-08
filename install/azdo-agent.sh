#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Name:         Azure DevOps Agent LXC Installer
# Description:  Deploy a self-hosted Azure DevOps Linux agent in an LXC container
# Author:       Based on Tteck’s community-scripts style
# GitHub:       https://github.com/JanuszNowak/ProxmoxVE
# -----------------------------------------------------------------------------

set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --- Colors ---
YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"

# --- Source build helper ---
REPO="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
source <(curl -fsSL "${REPO}/misc/build.func")

# --- Required vars for build.func ---
: "${BRG:=vmbr0}"
: "${RANDOM_UUID:=$(cat /proc/sys/kernel/random/uuid)}"
: "${NSAPP:=Azure DevOps Agent}"

# --- Container defaults ---
APP="azdo-agent"
var_disk="10"
var_cpu="2"
var_ram="4096"
var_os="ubuntu"
var_version="22.04"
var_features="nesting=1,keyctl=1,fuse=1"

# --- Prompt user ---
header_info "Azure DevOps Agent LXC Installer"

read -rp "Azure DevOps Organization URL (e.g. https://dev.azure.com/YourOrg): " AZDO_URL
read -rp "Personal Access Token (PAT): " AZDO_PAT
read -rp "Agent Pool name [Default]: " AZDO_POOL
AZDO_POOL=${AZDO_POOL:-Default}
read -rp "Agent name [lxc-agent]: " AZDO_NAME
AZDO_NAME=${AZDO_NAME:-lxc-agent}

# Optional: Install Docker and build tools
read -rp "Install Docker + build tools? (y/N): " RESP
RESP=${RESP,,}
INSTALL_TOOLS=false
if [[ "$RESP" == "y" || "$RESP" == "yes" ]]; then
  INSTALL_TOOLS=true
fi

# --- Create LXC container ---
build_container

# --- Post-install inside container ---
post_install() {
  echo -e "${YW}→ Updating packages and installing dependencies...${CL}"
  apt-get update -y
  apt-get install -y --no-install-recommends \
    curl git jq unzip ca-certificates apt-transport-https sudo

  # Optional developer tools
  if [ "$INSTALL_TOOLS" = true ]; then
    echo -e "${YW}→ Installing Docker and build tools...${CL}"
    curl -fsSL https://get.docker.com | bash
    apt-get install -y build-essential python3 python3-pip dotnet-sdk-6.0 nodejs npm
  fi

  # Create agent user
  echo -e "${YW}→ Creating azdo user...${CL}"
  useradd -m -s /bin/bash azdo || true
  echo "azdo ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/azdo
  chmod 0440 /etc/sudoers.d/azdo

  # Download and configure agent
  echo -e "${YW}→ Downloading Azure DevOps agent...${CL}"
  su - azdo <<'EOF'
set -e
cd ~
AGENT_VERSION=$(curl -fsSL https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r .tag_name | sed 's/^v//')
wget -q "https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"
mkdir agent && cd agent
tar zxvf "../vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"

./config.sh --unattended \
  --url "${AZDO_URL}" \
  --auth pat \
  --token "${AZDO_PAT}" \
  --pool "${AZDO_POOL}" \
  --agent "${AZDO_NAME}" \
  --work _work \
  --replace \
  --acceptTeeEula
EOF

  # Add Docker group if needed
  if [ "$INSTALL_TOOLS" = true ]; then
    usermod -aG docker azdo
  fi

  # Install and start service
  echo -e "${YW}→ Installing and starting agent service...${CL}"
  su - azdo -c "cd ~/agent && sudo ./svc.sh install"
  su - azdo -c "cd ~/agent && sudo ./svc.sh start"

  echo -e "${GN}✅ Azure DevOps Agent installation complete!${CL}"
  echo -e "Agent name: ${BL}${AZDO_NAME}${CL}"
  echo -e "URL:        ${BL}${AZDO_URL}${CL}"
  echo -e "Pool:       ${BL}${AZDO_POOL}${CL}"
  echo -e "Docker:     ${BL}${INSTALL_TOOLS}${CL}"
}

# Run post_install in container
post_install
