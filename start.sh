#!/bin/bash
set -e

if [ -z "$AZP_URL" ]; then
  echo 1>&2 "error: missing AZP_URL environment variable"
  exit 1
fi

if [ -z "$AZP_TOKEN_FILE" ]; then
  if [ -z "$AZP_TOKEN" ]; then
    echo 1>&2 "error: missing AZP_TOKEN environment variable"
    exit 1
  fi

  AZP_TOKEN_FILE=/azp/.token
  echo -n $AZP_TOKEN > "$AZP_TOKEN_FILE"
fi

unset AZP_TOKEN

if [ -n "$AZP_WORK" ]; then
  mkdir -p "$AZP_WORK"
fi

export AGENT_ALLOW_RUNASROOT="1"

cleanup() {
  if [ -e config.sh ]; then
    print_header "Cleanup. Removing Azure Pipelines agent..."

    # If the agent has some running jobs, the configuration removal process will fail.
    # So, give it some time to finish the job.
    while true; do
      ./config.sh remove --unattended --auth PAT --token $(cat "$AZP_TOKEN_FILE") && break

      echo "Retrying in 30 seconds..."
      sleep 30
    done
  fi
}

print_header() {
  lightcyan='\033[1;36m'
  nocolor='\033[0m'
  echo -e "${lightcyan}$1${nocolor}"
}

# Let the agent ignore the token env variables
export VSO_AGENT_IGNORE=AZP_TOKEN,AZP_TOKEN_FILE

source ./env.sh

print_header "1. Configuring Azure Pipelines agent..."

./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "$AZP_URL" \
  --auth PAT \
  --token $(cat "$AZP_TOKEN_FILE") \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula & wait $!

print_header "2. Running Azure Pipelines agent..."

trap 'cleanup; exit 0' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

print_header "3. Starting docker and cron services"

start_docker() {
  if docker info >/dev/null 2>&1; then
    echo "docker daemon already running"
    return 0
  fi

  # Raise limits ourselves where the kernel allows it. /etc/init.d/docker sets
  # these unconditionally and aborts when the container rejects them, which under
  # `set -e` would tear down the agent, so start dockerd directly instead.
  ulimit -n 1048576 2>/dev/null || echo 1>&2 "warning: could not raise nofile limit"
  ulimit -u unlimited 2>/dev/null || echo 1>&2 "warning: could not raise nproc limit"

  dockerd >>/var/log/dockerd.log 2>&1 &

  local i
  for i in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
      echo "docker daemon ready after ${i}s"
      return 0
    fi
    sleep 1
  done

  echo 1>&2 "warning: docker daemon not ready after 60s; see /var/log/dockerd.log"
  return 1
}

# A failure here must not kill the agent: jobs that do not need Docker can still run.
start_docker || true
service cron start || echo 1>&2 "warning: failed to start cron"

# To be aware of TERM and INT signals call run.sh
# Running it with the --once flag at the end will shut down the agent after the build is executed
./run.sh "$@" &

wait $!