#!/usr/bin/env bash
set -euo pipefail

NETWORK="${NETWORK:-jiranet}"
PG_CONTAINER="jira-postgres"; PG_USER="jira"; PG_PASSWORD="jira"
JIRA_DB="jiradb"; BB_DB="bitbucketdb"
JIRA_PORT=8080; BB_PORT=7990; BB_SSH_PORT=7999
JIRA_IMAGE="atlassian/jira-software"; BB_IMAGE="atlassian/bitbucket"; PG_IMAGE="postgres:15"

BB_LICENSE="${BB_LICENSE:-}"
BB_ADMIN_USER="${BB_ADMIN_USER:-bit}"; BB_ADMIN_PASS="${BB_ADMIN_PASS:-bit}"
BB_ADMIN_NAME="${BB_ADMIN_NAME:-Bitbucket Admin}"; BB_ADMIN_EMAIL="${BB_ADMIN_EMAIL:-admin@example.com}"

c_reset="\033[0m"; c_blue="\033[1;34m"; c_green="\033[1;32m"; c_yellow="\033[1;33m"; c_red="\033[1;31m"; c_dim="\033[2m"
log(){ echo -e "${c_blue}> ${c_reset}$*"; }
ok(){ echo -e "${c_green}OK ${c_reset}$*"; }
warn(){ echo -e "${c_yellow}! ${c_reset}$*"; }
err(){ echo -e "${c_red}X ${c_reset}$*" >&2; }
hr(){ echo -e "${c_dim}--------------------------------------------------------------${c_reset}"; }

log "Waiting for Docker daemon..."
for i in $(seq 1 30); do
  docker info >/dev/null 2>&1 && { ok "Docker is up."; break; }
  sleep 2; [[ $i -eq 30 ]] && { err "Docker daemon not ready."; exit 1; }
done

if [[ -n "${CODESPACE_NAME:-}" ]]; then
  DOMAIN="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
  JIRA_HOST="${CODESPACE_NAME}-${JIRA_PORT}.${DOMAIN}"
  BB_HOST="${CODESPACE_NAME}-${BB_PORT}.${DOMAIN}"; IN_CS=1
else
  JIRA_HOST="localhost:${JIRA_PORT}"; BB_HOST="localhost:${BB_PORT}"; IN_CS=0
fi

echo; hr; echo -e "${c_green}  Auto-Setup - Jira + Bitbucket Lab${c_reset}"; hr
echo -e "  Jira      : https://${JIRA_HOST}"
echo -e "  Bitbucket : https://${BB_HOST}"
hr; echo

log "Network '${NETWORK}'..."
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
ok "Network ready."

log "PostgreSQL..."
if docker ps -a --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  docker start "$PG_CONTAINER" >/dev/null
else
  docker run -d --name "$PG_CONTAINER" --network "$NETWORK" \
    -e POSTGRES_USER="$PG_USER" -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRES_DB="$JIRA_DB" "$PG_IMAGE" >/dev/null
fi
for i in $(seq 1 30); do
  docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" >/dev/null 2>&1 && { ok "Postgres ready."; break; }
  sleep 2; [[ $i -eq 30 ]] && { err "Postgres not ready."; exit 1; }
done
docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$JIRA_DB" -tc \
  "SELECT 1 FROM pg_database WHERE datname='${BB_DB}'" | grep -q 1 \
  || docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$JIRA_DB" -c "CREATE DATABASE ${BB_DB};" >/dev/null
ok "Databases ready (${JIRA_DB}, ${BB_DB})."

log "Jira..."
docker rm -f jira >/dev/null 2>&1 || true
docker run -d --name jira --network "$NETWORK" -p "${JIRA_PORT}:8080" \
  -e ATL_TOMCAT_SCHEME=https -e ATL_TOMCAT_SECURE=true \
  -e ATL_PROXY_NAME="${JIRA_HOST%%:*}" -e ATL_PROXY_PORT=443 \
  -e ATL_DB_TYPE=postgres72 -e ATL_DB_DRIVER=org.postgresql.Driver \
  -e ATL_JDBC_URL="jdbc:postgresql://${PG_CONTAINER}:5432/${JIRA_DB}" \
  -e ATL_JDBC_USER="${PG_USER}" -e ATL_JDBC_PASSWORD="${PG_PASSWORD}" \
  "$JIRA_IMAGE" >/dev/null
ok "Jira started (DB pre-configured)."

log "Bitbucket..."
docker rm -f bitbucket >/dev/null 2>&1 || true
BB_ENVS=(
  -e SERVER_PROXY_NAME="${BB_HOST%%:*}" -e SERVER_PROXY_PORT=443
  -e SERVER_SCHEME=https -e SERVER_SECURE=true
  -e JDBC_DRIVER=org.postgresql.Driver
  -e JDBC_URL="jdbc:postgresql://${PG_CONTAINER}:5432/${BB_DB}"
  -e JDBC_USER="${PG_USER}" -e JDBC_PASSWORD="${PG_PASSWORD}"
)
if [[ -n "$BB_LICENSE" ]]; then
  BB_ENVS+=(
    -e SETUP_DISPLAYNAME="Bitbucket" -e SETUP_BASEURL="https://${BB_HOST%%:*}"
    -e SETUP_LICENSE="${BB_LICENSE}"
    -e SETUP_SYSADMIN_USERNAME="${BB_ADMIN_USER}" -e SETUP_SYSADMIN_PASSWORD="${BB_ADMIN_PASS}"
    -e SETUP_SYSADMIN_DISPLAYNAME="${BB_ADMIN_NAME}" -e SETUP_SYSADMIN_EMAILADDRESS="${BB_ADMIN_EMAIL}"
  )
fi
docker run -d --name bitbucket --network "$NETWORK" \
  -p "${BB_PORT}:7990" -p "${BB_SSH_PORT}:7999" "${BB_ENVS[@]}" "$BB_IMAGE" >/dev/null
ok "Bitbucket started."

if [[ "$IN_CS" == "1" ]] && command -v gh >/dev/null 2>&1; then
  log "Setting ports public..."
  gh codespace ports visibility "${JIRA_PORT}:public" "${BB_PORT}:public" -c "$CODESPACE_NAME" >/dev/null 2>&1 \
    && ok "Ports 8080 & 7990 are public." \
    || warn "Set later: gh codespace ports visibility 8080:public 7990:public -c \$CODESPACE_NAME"
fi

wait_ready(){ local port="$1" label="$2" tries="${3:-72}"
  log "Waiting for ${label} (1-3 min)..."
  for i in $(seq 1 "$tries"); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${port}/status" 2>/dev/null || echo 000)"
    [[ "$code" =~ ^(200|302|401|403)$ ]] && { ok "${label} responding (HTTP ${code})."; return 0; }
    sleep 5
  done
  warn "${label} still starting - check: docker logs ${label,,}"
}
wait_ready "$JIRA_PORT" "Jira" 60
wait_ready "$BB_PORT" "Bitbucket" 72

echo; hr; echo -e "${c_green}  READY${c_reset}"; hr
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E "NAMES|jira|bitbucket|postgres" || true
echo
echo -e "${c_blue}OPEN:${c_reset}  Jira https://${JIRA_HOST}   |   Bitbucket https://${BB_HOST}"
echo
echo -e "${c_blue}REMAINING:${c_reset}"
echo -e "  Jira  : DB auto-filled -> apply LICENSE + create ADMIN in the wizard."
[[ -n "$BB_LICENSE" ]] \
  && echo -e "  Bitbucket : provisioned (admin: ${BB_ADMIN_USER}/${BB_ADMIN_PASS})" \
  || echo -e "  Bitbucket : short wizard (license + admin) - or set BB_LICENSE secret."
hr; echo
