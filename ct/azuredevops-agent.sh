#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2025 community-scripts ORG
# Author: YourName
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/linux-agent

APP="AzureDevOps Agent"
var_tags="${var_tags:-ci;devops;azure;agent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID="$NEXTID"
  HN="azuredevops-agent"
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  PCT_OSTYPE="$var_os"
  PCT_OSVERSION="$var_version"
  UNPRIVILEGED="$var_unprivileged"
  FEATURES="keyctl=1,nesting=1"
  SSH="no"
  VERBOSE="no"
}

function update_script() {
  header_info
  check_container_storage
  check_variables
  check_ctid_unused
  network_check
  arch_check
  pve_version_check
  ssh_check
}

function prompt_azuredevops_settings() {
  msg_info "Collecting Azure DevOps configuration"

  while true; do
    read -r -p "Azure DevOps Organization URL (e.g. https://dev.azure.com/yourorg): " AZP_URL
    [[ -n "$AZP_URL" && "$AZP_URL" =~ ^https:// ]] && break
    msg_error "Organization URL must not be empty and must start with https://"
  done

  while true; do
    read -r -p "Agent Pool Name: " AZP_POOL
    [[ -n "$AZP_POOL" ]] && break
    msg_error "Agent Pool Name cannot be empty"
  done

  read -r -p "Agent Name [${HN}]: " AZP_AGENT_NAME
  AZP_AGENT_NAME="${AZP_AGENT_NAME:-$HN}"

  while true; do
    read -r -s -p "Personal Access Token (PAT): " AZP_TOKEN
    echo
    [[ -n "$AZP_TOKEN" ]] && break
    msg_error "PAT cannot be empty"
  done

  msg_ok "Azure DevOps configuration collected"
}

function install_azuredevops_agent() {
  msg_info "Installing dependencies"
  pct exec "$CT_ID" -- bash -c "apt-get update && apt-get install -y curl sudo jq git ca-certificates tar libicu72"
  msg_ok "Installed dependencies"

  msg_info "Creating service user"
  pct exec "$CT_ID" -- bash -c "id -u azureagent >/dev/null 2>&1 || useradd -m -s /bin/bash azureagent"
  msg_ok "Created service user"

  msg_info "Detecting latest Azure Pipelines agent version"
  AGENT_VERSION="$(curl -fsSL https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  if [[ -z "$AGENT_VERSION" || "$AGENT_VERSION" == "null" ]]; then
    msg_error "Unable to determine latest Azure Pipelines agent version"
    exit 1
  fi
  msg_ok "Using agent version ${AGENT_VERSION}"

  msg_info "Downloading Azure Pipelines agent"
  pct exec "$CT_ID" -- bash -c "
    set -e
    install -d -o azureagent -g azureagent /home/azureagent/agent
    cd /home/azureagent/agent
    curl -fsSL -o agent.tar.gz https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz
    tar -xzf agent.tar.gz
    chown -R azureagent:azureagent /home/azureagent/agent
  "
  msg_ok "Downloaded Azure Pipelines agent"

  msg_info "Writing Azure DevOps configuration"
  pct exec "$CT_ID" -- bash -c "cat > /home/azureagent/agent/.azdo.env <<'EOF'
AZP_URL=$(printf '%s' "$AZP_URL")
AZP_POOL=$(printf '%s' "$AZP_POOL")
AZP_AGENT_NAME=$(printf '%s' "$AZP_AGENT_NAME")
AZP_TOKEN=$(printf '%s' "$AZP_TOKEN")
EOF
chown azureagent:azureagent /home/azureagent/agent/.azdo.env
chmod 600 /home/azureagent/agent/.azdo.env"
  msg_ok "Configuration file created"

  msg_info "Configuring Azure Pipelines agent"
  pct exec "$CT_ID" -- bash -c "
    set -a
    . /home/azureagent/agent/.azdo.env
    set +a
    cd /home/azureagent/agent
    sudo -u azureagent ./config.sh --unattended \
      --url \"\$AZP_URL\" \
      --auth pat \
      --token \"\$AZP_TOKEN\" \
      --pool \"\$AZP_POOL\" \
      --agent \"\$AZP_AGENT_NAME\" \
      --acceptTeeEula \
      --work _work \
      --replace
  "
  msg_ok "Configured Azure Pipelines agent"

  msg_info "Installing Azure Pipelines service"
  pct exec "$CT_ID" -- bash -c "
    cd /home/azureagent/agent
    ./svc.sh install azureagent
    ./svc.sh start
  "
  msg_ok "Installed and started Azure Pipelines service"

  msg_info "Verifying service status"
  pct exec "$CT_ID" -- bash -c "systemctl --no-pager --full status 'vsts.agent.*' || true"
  msg_ok "Service verification completed"
}

start
build_container
description
prompt_azuredevops_settings
install_azuredevops_agent
motd_ssh
customize

msg_ok "Completed Successfully!"
echo -e "${APP} LXC is ready."
echo -e "Container ID: ${CT_ID}"
echo -e "Enter the container with: pct enter ${CT_ID}"
