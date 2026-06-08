#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2025 community-scripts ORG
# Author: JanuszNowak
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.github.com/en/actions/hosting-your-own-runners

APP="GitHub Runner"
var_tags="${var_tags:-ci;github;actions;runner}"
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
  HN="github-runner"
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

function prompt_github_runner_settings() {
  msg_info "Collecting GitHub Runner configuration"

  while true; do
    read -r -p "GitHub Repository or Organization URL (e.g. https://github.com/owner/repo or https://github.com/org): " GH_URL
    [[ -n "$GH_URL" && "$GH_URL" =~ ^https://github\.com/[^/]+(/[^/]+)?/?$ ]] && break
    msg_error "GitHub URL must be a valid repository or organization URL"
  done

  while true; do
    read -r -p "Runner Scope Type [repo/org]: " GH_SCOPE
    [[ "$GH_SCOPE" == "repo" || "$GH_SCOPE" == "org" ]] && break
    msg_error "Scope type must be 'repo' or 'org'"
  done

  while true; do
    read -r -s -p "GitHub Personal Access Token (PAT): " GH_PAT
    echo
    [[ -n "$GH_PAT" ]] && break
    msg_error "GitHub PAT cannot be empty"
  done

  read -r -p "Runner Name [${HN}]: " GH_RUNNER_NAME
  GH_RUNNER_NAME="${GH_RUNNER_NAME:-$HN}"

  read -r -p "Runner Labels [linux,x64,lxc]: " GH_LABELS
  GH_LABELS="${GH_LABELS:-linux,x64,lxc}"

  read -r -p "Work Folder [_work]: " GH_WORK
  GH_WORK="${GH_WORK:-_work}"

  msg_ok "GitHub Runner configuration collected"
}

function parse_github_url() {
  local stripped path_parts
  stripped="${GH_URL#https://github.com/}"
  stripped="${stripped%/}"

  IFS='/' read -r GH_OWNER GH_REPO <<< "$stripped"

  if [[ "$GH_SCOPE" == "repo" ]]; then
    if [[ -z "$GH_OWNER" || -z "$GH_REPO" ]]; then
      msg_error "Repository scope requires URL like https://github.com/owner/repo"
      exit 1
    fi
    GH_API_URL="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token"
  else
    if [[ -z "$GH_OWNER" ]]; then
      msg_error "Organization scope requires URL like https://github.com/org"
      exit 1
    fi
    GH_API_URL="https://api.github.com/orgs/${GH_OWNER}/actions/runners/registration-token"
    GH_REPO=""
  fi
}

function get_runner_token() {
  msg_info "Requesting GitHub runner registration token"

  RESPONSE="$(curl -fsSL -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GH_PAT}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GH_API_URL}")" || {
      msg_error "Failed to request runner registration token"
      exit 1
    }

  GH_TOKEN="$(echo "$RESPONSE" | jq -r '.token')"

  if [[ -z "$GH_TOKEN" || "$GH_TOKEN" == "null" ]]; then
    msg_error "GitHub API did not return a registration token"
    echo "$RESPONSE"
    exit 1
  fi

  msg_ok "Runner registration token acquired"
}

function install_github_runner() {
  msg_info "Installing dependencies"
  pct exec "$CT_ID" -- bash -c "apt-get update && apt-get install -y curl sudo jq git ca-certificates tar libicu72"
  msg_ok "Installed dependencies"

  msg_info "Creating service user"
  pct exec "$CT_ID" -- bash -c "id -u githubrunner >/dev/null 2>&1 || useradd -m -s /bin/bash githubrunner"
  msg_ok "Created service user"

  msg_info "Detecting latest GitHub Actions runner version"
  RUNNER_VERSION="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  if [[ -z "$RUNNER_VERSION" || "$RUNNER_VERSION" == "null" ]]; then
    msg_error "Unable to determine latest GitHub Actions runner version"
    exit 1
  fi
  msg_ok "Using runner version ${RUNNER_VERSION}"

  msg_info "Testing network connectivity"
  pct exec "$CT_ID" -- bash -c "
    getent hosts github.com >/dev/null 2>&1 || exit 1
    getent hosts api.github.com >/dev/null 2>&1 || exit 2
    getent hosts objects.githubusercontent.com >/dev/null 2>&1 || exit 3
  "
  msg_ok "Network connectivity looks good"

  msg_info "Downloading GitHub Actions runner"
  pct exec "$CT_ID" -- bash -c "
    set -e
    install -d -o githubrunner -g githubrunner /home/githubrunner/actions-runner
    cd /home/githubrunner/actions-runner
    curl -fsSL -o actions-runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    tar -xzf actions-runner.tar.gz
    chown -R githubrunner:githubrunner /home/githubrunner/actions-runner
  "
  msg_ok "Downloaded GitHub Actions runner"

  msg_info "Writing GitHub Runner configuration"
  ESC_GH_URL="$(printf '%q' "$GH_URL")"
  ESC_GH_TOKEN="$(printf '%q' "$GH_TOKEN")"
  ESC_GH_RUNNER_NAME="$(printf '%q' "$GH_RUNNER_NAME")"
  ESC_GH_LABELS="$(printf '%q' "$GH_LABELS")"
  ESC_GH_WORK="$(printf '%q' "$GH_WORK")"

  pct exec "$CT_ID" -- bash -c "
    cat > /home/githubrunner/actions-runner/.github-runner.env <<EOF
GH_URL=${ESC_GH_URL}
GH_TOKEN=${ESC_GH_TOKEN}
GH_RUNNER_NAME=${ESC_GH_RUNNER_NAME}
GH_LABELS=${ESC_GH_LABELS}
GH_WORK=${ESC_GH_WORK}
EOF
    chown githubrunner:githubrunner /home/githubrunner/actions-runner/.github-runner.env
    chmod 600 /home/githubrunner/actions-runner/.github-runner.env
  "
  msg_ok "Configuration file created"

  msg_info "Configuring GitHub Actions runner"
  pct exec "$CT_ID" -- bash -c "
    set -a
    . /home/githubrunner/actions-runner/.github-runner.env
    set +a
    cd /home/githubrunner/actions-runner
    sudo -u githubrunner ./config.sh \
      --unattended \
      --url \"\$GH_URL\" \
      --token \"\$GH_TOKEN\" \
      --name \"\$GH_RUNNER_NAME\" \
      --labels \"\$GH_LABELS\" \
      --work \"\$GH_WORK\" \
      --replace
  "
  msg_ok "Configured GitHub Actions runner"

  msg_info "Installing GitHub Actions runner service"
  pct exec "$CT_ID" -- bash -c "
    cd /home/githubrunner/actions-runner
    ./svc.sh install githubrunner
    ./svc.sh start
  "
  msg_ok "Installed and started GitHub Actions runner service"

  msg_info "Verifying service status"
  pct exec "$CT_ID" -- bash -c "systemctl --no-pager --full status 'actions.runner.*' || true"
  msg_ok "Service verification completed"
}

start
build_container
description
prompt_github_runner_settings
parse_github_url
get_runner_token
install_github_runner

if declare -f motd_ssh >/dev/null 2>&1; then
  motd_ssh
fi

customize

msg_ok "Completed Successfully!"
echo -e "${APP} LXC is ready."
echo -e "Container ID: ${CT_ID}"
echo -e "Enter the container with: pct enter ${CT_ID}"
