#!/usr/bin/env bash
set -euo pipefail

###########################################################
# PROJECT SETTINGS
###########################################################

# Where your project lives inside WSL
PROJECT_DIR="/home/opatel/PROJECT"

# Nginx runs on port 80, so this is where the main site loads
APP_URL="http://localhost"

# Addresses for the services we want to check
BACKEND_URL="http://localhost:5000"
TRANSACTIONS_URL="http://localhost:4000"
STUDENT_PORTFOLIO_URL="http://localhost:3000"

# Common names used across this script
COMPOSE_FILE="docker-compose.yml"
NGINX_IMAGE="nginx:alpine"
NGINX_LOG_FILE="nginx-logs.txt"

###########################################################
# HELPER FUNCTIONS
###########################################################

# Print a message with a timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Show an error and stop the script
fail() {
  log "ERROR: $*"
  exit 1
}

# Make sure a needed command is installed
check_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "Missing required command: $cmd"
  fi
}

# Find out whether this machine uses “docker-compose” or “docker compose”
get_compose_cmd() {
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo "docker compose"
  fi
}

# Ensure the port is available before containers start
check_port_free() {
  local port="$1"
  if ss -tulpn 2>/dev/null | awk '{print $5}' | grep -q ":${port}\$"; then
    fail "Port ${port} is already in use. Close the program using it first."
  fi
}

# Keep checking a service until it replies
health_check_http() {
  local url="$1"
  local service="$2"
  local attempt=1
  local max_attempts=15
  local wait=4

  log "Checking if ${service} is up at ${url}"

  while (( attempt <= max_attempts )); do
    if curl -sSf "${url}" >/dev/null 2>&1; then
      log " ${service} is working (attempt ${attempt})"
      return 0
    fi

    log "Still waiting for ${service}... attempt ${attempt}/${max_attempts}"
    sleep "${wait}"
    attempt=$((attempt+1))
  done

  fail "${service} did not respond in time"
}

# Install jq if missing (we use it to read JSON)
ensure_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log "jq is not installed — adding it now..."
    sudo apt-get update
    sudo apt-get install -y jq
  fi
}

# Inspect the nginx image and save details
inspect_nginx_image() {
  log "Collecting details about the nginx image..."

  ensure_jq

  docker inspect "${NGINX_IMAGE}" > "${NGINX_LOG_FILE}"
  log "Saved nginx details to ${NGINX_LOG_FILE}"

  log "RepoTags:"
  jq '.[0].RepoTags' "${NGINX_LOG_FILE}"

  log "Created:"
  jq '.[0].Created' "${NGINX_LOG_FILE}"

  log "Operating system:"
  jq '.[0].Os' "${NGINX_LOG_FILE}"

  log "Configuration:"
  jq '.[0].Config' "${NGINX_LOG_FILE}"

  log "Exposed ports:"
  jq '.[0].Config.ExposedPorts' "${NGINX_LOG_FILE}"
}

# Find the container ID of the running nginx instance
capture_nginx_container_id() {
  log "Looking for the active nginx container..."

  local cid
  cid=$(docker ps --filter "ancestor=${NGINX_IMAGE}" --format '{{.ID}}' | head -n 1 || true)

  if [[ -z "${cid}" ]]; then
    fail "Could not locate a running nginx container."
  fi

  NGINX_CONTAINER_ID="${cid}"
  log "nginx container ID: ${NGINX_CONTAINER_ID}"
}

###########################################################
# MAIN PROCESS
###########################################################

log "========== Starting Pixel River Financial Bank Setup =========="

# 1. Check required tools
log "Checking that Docker is ready..."
check_command docker
COMPOSE_BIN=$(get_compose_cmd)
log "Using compose command: ${COMPOSE_BIN}"

# 2. Go into project folder
log "Opening project folder: ${PROJECT_DIR}"

if [[ ! -d "${PROJECT_DIR}" ]]; then
  fail "Project folder not found."
fi

cd "${PROJECT_DIR}"

# 3. Make sure docker-compose.yml exists
log "Looking for docker-compose.yml..."
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  fail "${COMPOSE_FILE} was not found in this folder."
fi

# 4. Confirm ports we need are free
log "Checking ports 80, 3000, and 5000..."
for p in 80 3000 5000; do
  check_port_free "$p"
done
log "All needed ports are free."

# 5. Build and start containers
log "Building and starting the services..."
${COMPOSE_BIN} -f "${COMPOSE_FILE}" up -d --build
log "Everything is now running."

# 6. Show Docker state
log "Docker Images:"
docker images

log "Running Containers:"
docker ps

# 7. Find the nginx container ID
capture_nginx_container_id

# 8. Run health checks
log "Checking backend on port 5000..."
health_check_http "${BACKEND_URL}" "Backend"

log "Checking student portfolio on port 3000..."
health_check_http "${STUDENT_PORTFOLIO_URL}" "Student Portfolio"

# Transactions service is internal, so no direct check here

# 9. Make sure nginx is responding
log "Checking main nginx site..."
health_check_http "${APP_URL}" "nginx front-end"

# 10. Inspect nginx image and store info
inspect_nginx_image

log "========== Setup complete. You can open the site at ${APP_URL} =========="

