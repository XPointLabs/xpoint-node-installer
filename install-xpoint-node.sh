#!/usr/bin/env bash
set -Eeuo pipefail

INSTALLER_VERSION="0.7.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${XPOINT_NODE_DIR:-/opt/xpoint-node}"
NON_INTERACTIVE=0
START_NODE=1
ROTATE_REALITY=0
PRUNE_DOCKER=0
REALITY_MODE="${XPOINT_REALITY_MODE:-prompt}"
CERTIFICATE_PROFILE="${XPOINT_CERTIFICATE_PROFILE:-pinned-self-issued}"
RECEIVE_POSITION_ARG=""
IMPORT_DIR_ARG=""
UPGRADE_DIR_ARG=""
PEER_ARGS=()
ROLLBACK_DIR=""
ROLLBACK_REQUIRED=0

PUBLIC_HOST_ARG=""
PUBLIC_PORT_ARG=""
OPERATOR_ADDRESS_ARG=""
REWARDS_ADDRESS_ARG=""
REGISTRY_URL_ARG=""
STAKING_BACKEND_URL_ARG=""
RPC_URL_ARG=""
FALLBACK_RPC_URLS_ARG=""
PEER_RPC_PORT_ARG=""
XNODE_IMAGE_ARG=""
STORAGE_IMAGE_ARG=""
DOCKER_LOG_MAX_SIZE_ARG=""
DOCKER_LOG_MAX_FILE_ARG=""
SCANNER_ADDR="${XPOINT_REALITY_SCAN_ADDR:-}"
SCANNER_URL="${XPOINT_REALITY_SCAN_URL:-}"
SCANNER_THREADS="${XPOINT_REALITY_SCAN_THREADS:-16}"
SCANNER_TIMEOUT="${XPOINT_REALITY_SCAN_TIMEOUT:-5}"
SCANNER_MAX_SECONDS="${XPOINT_REALITY_SCAN_MAX_SECONDS:-60}"

PROD_STAKE_ATOMIC="25000000000000"
PROD_SERVICE_NODE_REWARDS="0xc52284b7aBAebbEF7BdE0E1ca8251B44AeA12F5f"
DEFAULT_REGISTRY_URL="https://registry.xpoint.network"
DEFAULT_STAKING_BACKEND_URL="https://staking-api.xpoint.network"
DEFAULT_PUSH_NOTIFY_URL="https://push.xpoint.network/_compat/push-notify"
DEFAULT_ARBITRUM_RPC_URL="https://arb1.arbitrum.io/rpc"
DEFAULT_XNODE_IMAGE="ghcr.io/xpointlabs/xnode:latest"
DEFAULT_STORAGE_IMAGE="ghcr.io/xpointlabs/deep-storage-service:latest"
DEFAULT_REALITY_SNI="cloudflare-dns.com"
DEFAULT_DOCKER_LOG_MAX_SIZE="50m"
DEFAULT_DOCKER_LOG_MAX_FILE="5"
DEFAULT_MAX_REWARD_SIGNATURE_INCREASE_ATOMIC="100000000000000"
DEFAULT_QUORUM_POLICY_TIMEOUT_SECONDS="5"
DEFAULT_QUORUM_SIGNATURE_TIMESTAMP_SKEW_SECONDS="300"
DEFAULT_XPOINT_NETWORK_ID_HEX="edc5dc1516a847a65fc8ba0e690d000d"
DEFAULT_XPOINT_GENESIS_PIN_HEX="304911104767ae1036a44c71116a5fcdee3449fc71ea1467c09295f89be3a2b7"
DEFAULT_XPOINT_DIRECTORY_LEAF_KEY_HEX="3fd0371522bcfe473b36645f76a3817c722887fcbaa39ef75f4644a124d7b359"

COMPOSE_FILE=""
ENV_FILE=""
SECRETS_DIR=""
TOOLS_DIR=""
IDENTITY_SCRIPT=""
INGRESS_CONFIG_DIR=""
RUNTIME_SCRIPTS_DIR=""
DOCKER_CMD=()
COMPOSE_CMD=()

usage() {
  cat <<'USAGE'
Usage: install-xpoint-node.sh [options]

Install or update a production XPoint node on Linux.

Options:
  --dir DIR                    Installation directory (default: /opt/xpoint-node)
  --public-host HOST           Public DNS name or IP clients can reach
  --public-port PORT           Public VLESS Reality port (default: 443)
  --operator-address ADDRESS   Staking operator wallet
  --rewards-address ADDRESS    Staking rewards wallet
  --registry-url URL           Production registry URL
  --staking-backend-url URL    Production staking backend API URL
  --rpc-url URL                Arbitrum One RPC URL used by the node backend
  --fallback-rpc-urls URLS     Comma-separated fallback Arbitrum One RPC URLs
  --peer-rpc-port PORT         Public signed node-to-node RPC port (default: 22020)
  --receive-position ROLE      Onion role: Ingress, Core, or Exit
  --peer SPEC                  Peer as ROUTER_ID,HTTPS_BASE_URL,CURRENT_PIN,NEXT_PIN
                               (repeat exactly twice for the three-router topology)
  --import-dir DIR             Import an existing .env.node.prod and secrets directory
  --upgrade-dir DIR            Apply a staged env/secrets set to an existing node after
                               verifying that every existing secret is byte-identical
  --xnode-image IMAGE          XPoint node image
  --storage-image IMAGE        Per-node storage service image
  --docker-log-max-size SIZE   Docker json-file max-size (default: 50m)
  --docker-log-max-file COUNT  Docker json-file max-file (default: 5)
  --prune-docker               Remove stopped containers, unused images, and build cache
                               after update. Volumes are never pruned.
  --default-reality            Use the default Reality SNI
  --auto-sni                   Select Reality SNI with XTLS/RealiTLScanner
  --scanner-url URL            URL for RealiTLScanner crawl mode (overrides automatic node-IP scan)
  --scanner-addr TARGET        Explicit address/CIDR/domain override (default: node public IPv4)
  --scanner-threads N          Scanner worker count (default: 16)
  --scanner-timeout SECONDS    Scanner timeout (default: 5)
  --scanner-max-seconds N      Maximum total address scan time (default: 60)
  --rotate-reality             Regenerate Reality keys and re-apply SNI mode
  --no-start                   Prepare files but do not run docker compose up
  -y, --yes                    Non-interactive; use defaults and fail if required values stay missing
  -h, --help                   Show this help
USAGE
}

log() {
  printf '[xpoint-node] %s\n' "$*" >&2
}

warn() {
  printf '[xpoint-node] WARNING: %s\n' "$*" >&2
}

fail() {
  printf '[xpoint-node] ERROR: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dir) APP_DIR="${2:?missing value for --dir}"; shift 2 ;;
      --public-host) PUBLIC_HOST_ARG="${2:?missing value for --public-host}"; shift 2 ;;
      --public-port) PUBLIC_PORT_ARG="${2:?missing value for --public-port}"; shift 2 ;;
      --operator-address) OPERATOR_ADDRESS_ARG="${2:?missing value for --operator-address}"; shift 2 ;;
      --rewards-address) REWARDS_ADDRESS_ARG="${2:?missing value for --rewards-address}"; shift 2 ;;
      --registry-url) REGISTRY_URL_ARG="${2:?missing value for --registry-url}"; shift 2 ;;
      --staking-backend-url) STAKING_BACKEND_URL_ARG="${2:?missing value for --staking-backend-url}"; shift 2 ;;
      --rpc-url) RPC_URL_ARG="${2:?missing value for --rpc-url}"; shift 2 ;;
      --fallback-rpc-urls) FALLBACK_RPC_URLS_ARG="${2:?missing value for --fallback-rpc-urls}"; shift 2 ;;
      --peer-rpc-port) PEER_RPC_PORT_ARG="${2:?missing value for --peer-rpc-port}"; shift 2 ;;
      --receive-position) RECEIVE_POSITION_ARG="${2:?missing value for --receive-position}"; shift 2 ;;
      --peer) PEER_ARGS+=("${2:?missing value for --peer}"); shift 2 ;;
      --import-dir) IMPORT_DIR_ARG="${2:?missing value for --import-dir}"; shift 2 ;;
      --upgrade-dir) UPGRADE_DIR_ARG="${2:?missing value for --upgrade-dir}"; shift 2 ;;
      --xnode-image) XNODE_IMAGE_ARG="${2:?missing value for --xnode-image}"; shift 2 ;;
      --storage-image) STORAGE_IMAGE_ARG="${2:?missing value for --storage-image}"; shift 2 ;;
      --docker-log-max-size) DOCKER_LOG_MAX_SIZE_ARG="${2:?missing value for --docker-log-max-size}"; shift 2 ;;
      --docker-log-max-file) DOCKER_LOG_MAX_FILE_ARG="${2:?missing value for --docker-log-max-file}"; shift 2 ;;
      --prune-docker) PRUNE_DOCKER=1; shift ;;
      --default-reality) REALITY_MODE="default"; shift ;;
      --auto-sni) REALITY_MODE="scan"; shift ;;
      --scanner-url) SCANNER_URL="${2:?missing value for --scanner-url}"; SCANNER_ADDR=""; shift 2 ;;
      --scanner-addr) SCANNER_ADDR="${2:?missing value for --scanner-addr}"; SCANNER_URL=""; shift 2 ;;
      --scanner-threads) SCANNER_THREADS="${2:?missing value for --scanner-threads}"; shift 2 ;;
      --scanner-timeout) SCANNER_TIMEOUT="${2:?missing value for --scanner-timeout}"; shift 2 ;;
      --scanner-max-seconds) SCANNER_MAX_SECONDS="${2:?missing value for --scanner-max-seconds}"; shift 2 ;;
      --rotate-reality) ROTATE_REALITY=1; shift ;;
      --no-start) START_NODE=0; shift ;;
      -y|--yes) NON_INTERACTIVE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  [ -z "$IMPORT_DIR_ARG" ] || [ -z "$UPGRADE_DIR_ARG" ] \
    || fail "--import-dir and --upgrade-dir are mutually exclusive."

  COMPOSE_FILE="$APP_DIR/docker-compose.node.prod.yml"
  ENV_FILE="$APP_DIR/.env.node.prod"
  SECRETS_DIR="$APP_DIR/secrets"
  TOOLS_DIR="$APP_DIR/tools"
  IDENTITY_SCRIPT="$APP_DIR/new-xnode-identity.mjs"
  INGRESS_CONFIG_DIR="$APP_DIR/config/production-ingress"
  RUNTIME_SCRIPTS_DIR="$APP_DIR/scripts"
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_linux() {
  [ "$(uname -s)" = "Linux" ] || fail "This installer targets Linux hosts."
}

ensure_base_packages() {
  if ! command_exists apt-get; then
    fail "Only apt-based Linux distributions are automated for now. Install Docker, curl, openssl, git, nodejs, and python3 manually, then rerun."
  fi

  log "Installing base packages if missing"
  run_as_root apt-get update
  run_as_root apt-get install -y ca-certificates curl gnupg openssl git nodejs python3
}

ensure_docker() {
  if command_exists docker && docker compose version >/dev/null 2>&1; then
    log "Docker and Docker Compose are already installed"
  else
    log "Installing Docker Engine and Compose plugin"
    run_as_root install -m 0755 -d /etc/apt/keyrings
    . /etc/os-release
    local docker_os="${ID:-ubuntu}"
    case "$docker_os" in
      ubuntu|debian) ;;
      *) fail "Unsupported apt distribution for Docker repository: $docker_os" ;;
    esac
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      curl -fsSL "https://download.docker.com/linux/${docker_os}/gpg" \
        | run_as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      run_as_root chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${docker_os} ${VERSION_CODENAME} stable" \
      | run_as_root tee /etc/apt/sources.list.d/docker.list >/dev/null

    run_as_root apt-get update
    run_as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    run_as_root systemctl enable --now docker || true
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
    COMPOSE_CMD=(docker compose)
  elif sudo docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo docker)
    COMPOSE_CMD=(sudo docker compose)
  else
    fail "Docker is installed but not usable by this user. Try running with sudo or fix Docker permissions."
  fi

  "${COMPOSE_CMD[@]}" version >/dev/null
}

configure_docker_logging() {
  local log_max_size log_max_file
  log_max_size="$(env_get DEEP_DOCKER_LOG_MAX_SIZE | grep -E '.+' || printf '%s' "$DEFAULT_DOCKER_LOG_MAX_SIZE")"
  log_max_file="$(env_get DEEP_DOCKER_LOG_MAX_FILE | grep -E '.+' || printf '%s' "$DEFAULT_DOCKER_LOG_MAX_FILE")"
  require_docker_log_options "$log_max_size" "$log_max_file"

  if ! command_exists python3; then
    warn "python3 is unavailable; skipping Docker daemon log rotation merge."
    return
  fi

  log "Configuring Docker json-file log rotation (${log_max_size} x ${log_max_file})"
  run_as_root mkdir -p /etc/docker
  run_as_root env XPOINT_DOCKER_LOG_MAX_SIZE="$log_max_size" XPOINT_DOCKER_LOG_MAX_FILE="$log_max_file" python3 <<'PY'
import json
import os
import shutil
import time

path = "/etc/docker/daemon.json"
data = {}

if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        backup = f"{path}.bak-invalid-{int(time.time())}"
        shutil.copy2(path, backup)
        print(f"Existing daemon.json was invalid JSON; backed up to {backup}")
        data = {}

data["log-driver"] = "json-file"
log_opts = data.get("log-opts")
if not isinstance(log_opts, dict):
    log_opts = {}
log_opts["max-size"] = os.environ["XPOINT_DOCKER_LOG_MAX_SIZE"]
log_opts["max-file"] = os.environ["XPOINT_DOCKER_LOG_MAX_FILE"]
data["log-opts"] = log_opts

tmp = f"{path}.tmp"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp, path)
PY

  if command_exists systemctl; then
    run_as_root systemctl reload docker >/dev/null 2>&1 \
      || run_as_root systemctl kill -s HUP docker >/dev/null 2>&1 \
      || warn "Docker daemon reload failed; compose-level logging still applies to new node containers."
  fi
}

prune_docker_if_requested() {
  [ "$PRUNE_DOCKER" -eq 1 ] || return 0

  warn "--prune-docker removes stopped containers, unused images, and build cache. Docker volumes are not pruned."
  "${DOCKER_CMD[@]}" container prune -f
  "${DOCKER_CMD[@]}" image prune -af
  "${DOCKER_CMD[@]}" builder prune -af
}

ensure_app_dir() {
  log "Preparing $APP_DIR"
  run_as_root mkdir -p "$APP_DIR" "$SECRETS_DIR" "$TOOLS_DIR" "$APP_DIR/backups"
  if [ "$(id -u)" -ne 0 ]; then
    run_as_root chown -R "$(id -u):$(id -g)" "$APP_DIR"
  fi
  chmod 700 "$SECRETS_DIR"
}

import_existing_installation() {
  [ -n "$IMPORT_DIR_ARG" ] || return 0

  local source_dir
  source_dir="$(cd "$IMPORT_DIR_ARG" 2>/dev/null && pwd)" \
    || fail "Import directory does not exist: $IMPORT_DIR_ARG"
  [ "$source_dir" != "$APP_DIR" ] || fail "--import-dir must not be the installation directory itself."
  [ -f "$source_dir/.env.node.prod" ] || fail "Import directory is missing .env.node.prod."
  [ -d "$source_dir/secrets" ] || fail "Import directory is missing secrets/."
  [ ! -s "$ENV_FILE" ] || fail "Refusing to import over an existing non-empty $ENV_FILE."
  [ -z "$(find "$SECRETS_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ] \
    || fail "Refusing to import over a non-empty $SECRETS_DIR."

  log "Importing existing node configuration and secrets"
  install -m 0600 "$source_dir/.env.node.prod" "$ENV_FILE"
  cp -a "$source_dir/secrets/." "$SECRETS_DIR/"
  chmod 700 "$SECRETS_DIR"
  find "$SECRETS_DIR" -type f -exec chmod 600 {} +
}

apply_staged_upgrade() {
  [ -n "$UPGRADE_DIR_ARG" ] || return 0

  local source_dir source_secrets staged_env staged_secrets relative existing
  source_dir="$(cd "$UPGRADE_DIR_ARG" 2>/dev/null && pwd)" \
    || fail "Upgrade directory does not exist: $UPGRADE_DIR_ARG"
  source_secrets="$source_dir/secrets"
  [ "$source_dir" != "$APP_DIR" ] \
    || fail "--upgrade-dir must not be the installation directory itself."
  [ -s "$ENV_FILE" ] \
    || fail "--upgrade-dir requires an existing non-empty $ENV_FILE."
  [ -f "$source_dir/.env.node.prod" ] \
    || fail "Upgrade directory is missing .env.node.prod."
  [ -d "$source_secrets" ] \
    || fail "Upgrade directory is missing secrets/."
  [ -z "$(find "$source_secrets" -type l -print -quit)" ] \
    || fail "Upgrade secrets must not contain symbolic links."
  [ -z "$(find "$source_secrets" -mindepth 1 ! -type d ! -type f -print -quit)" ] \
    || fail "Upgrade secrets may contain only directories and regular files."

  for relative in key_ed25519 key_bls key_x25519 onion-state-protection.key \
      vless-client-id reality-private-key ingress/current.crt ingress/current.key \
      ingress/current.spki-sha256 ingress/next.crt ingress/next.key \
      ingress/next.spki-sha256; do
    [ -f "$source_secrets/$relative" ] \
      || fail "Upgrade directory is missing secrets/$relative."
    existing="$SECRETS_DIR/$relative"
    if [ -f "$existing" ] && ! cmp -s "$existing" "$source_secrets/$relative"; then
      fail "Staged upgrade would replace existing secrets/$relative; rotate it through an explicit authority workflow instead."
    fi
  done

  staged_env="$APP_DIR/.env.node.prod.upgrade-stage"
  staged_secrets="$APP_DIR/secrets.upgrade-stage"
  rm -rf "$staged_secrets"
  install -m 0600 "$source_dir/.env.node.prod" "$staged_env"
  mkdir -p "$staged_secrets"
  chmod 700 "$staged_secrets"
  cp -a "$source_secrets/." "$staged_secrets/"
  find "$staged_secrets" -type f -exec chmod 600 {} +

  log "Applying the verified staged production configuration"
  rm -rf "$SECRETS_DIR"
  mv "$staged_secrets" "$SECRETS_DIR"
  mv "$staged_env" "$ENV_FILE"
}

create_preupdate_backup() {
  if [ ! -f "$ENV_FILE" ] && [ ! -f "$COMPOSE_FILE" ] \
      && [ -z "$(find "$SECRETS_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    return 0
  fi

  local stamp backup_root
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_root="$APP_DIR/backups/pre-update-$stamp"
  mkdir -p "$backup_root"
  chmod 700 "$backup_root"

  tar --exclude='./backups' -C "$APP_DIR" -czf "$backup_root/config-and-secrets.tar.gz" \
    .env.node.prod docker-compose.node.prod.yml secrets config scripts 2>/dev/null || true
  if [ ! -s "$backup_root/config-and-secrets.tar.gz" ]; then
    rm -f "$backup_root/config-and-secrets.tar.gz"
    rmdir "$backup_root" 2>/dev/null || true
    return 0
  fi

  if [ -f "$COMPOSE_FILE" ] && [ -f "$ENV_FILE" ]; then
    (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --images 2>/dev/null || true) \
      | sort -u >"$backup_root/images.txt"
    local image image_id safe_name
    while IFS= read -r image; do
      [ -n "$image" ] || continue
      image_id="$("${DOCKER_CMD[@]}" image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)"
      [ -n "$image_id" ] || continue
      safe_name="$(printf '%s' "$image" | tr '/:@' '---' | tr -cd 'A-Za-z0-9_.-')"
      "${DOCKER_CMD[@]}" image tag "$image_id" "xpoint-rollback:${stamp}-${safe_name}"
      printf '%s\t%s\n' "$image" "xpoint-rollback:${stamp}-${safe_name}" >>"$backup_root/image-tags.tsv"
    done <"$backup_root/images.txt"
  fi

  ROLLBACK_DIR="$backup_root"
  log "Rollback snapshot created at $ROLLBACK_DIR"
}

restore_preupdate_backup() {
  [ -n "$ROLLBACK_DIR" ] || return 1
  [ -s "$ROLLBACK_DIR/config-and-secrets.tar.gz" ] || return 1

  warn "Update failed; restoring the pre-update configuration and image tags."
  if [ -s "$ROLLBACK_DIR/image-tags.tsv" ]; then
    local original rollback_tag
    while IFS=$'\t' read -r original rollback_tag; do
      [ -n "$original" ] && [ -n "$rollback_tag" ] || continue
      "${DOCKER_CMD[@]}" image tag "$rollback_tag" "$original"
    done <"$ROLLBACK_DIR/image-tags.tsv"
  fi
  rm -rf "$SECRETS_DIR" "$INGRESS_CONFIG_DIR" "$RUNTIME_SCRIPTS_DIR"
  rm -f "$ENV_FILE" "$COMPOSE_FILE"
  tar -C "$APP_DIR" -xzf "$ROLLBACK_DIR/config-and-secrets.tar.gz"
  chmod 700 "$SECRETS_DIR"
  find "$SECRETS_DIR" -type f -exec chmod 600 {} +
  (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --wait --remove-orphans)
}

write_compose_file() {
  INGRESS_CONFIG_DIR="${INGRESS_CONFIG_DIR:-$APP_DIR/config/production-ingress}"
  RUNTIME_SCRIPTS_DIR="${RUNTIME_SCRIPTS_DIR:-$APP_DIR/scripts}"
  local compose_asset="$SCRIPT_DIR/assets/docker-compose.node.prod.yml"
  local preflight_asset="$SCRIPT_DIR/assets/scripts/production-ingress-spki.mjs"
  local entrypoint_asset="$SCRIPT_DIR/assets/scripts/production-ingress-entrypoint.sh"
  local haproxy_asset="$SCRIPT_DIR/assets/config/production-ingress/haproxy.cfg.template"
  for asset in "$compose_asset" "$preflight_asset" "$entrypoint_asset" "$haproxy_asset"; do
    [ -f "$asset" ] || fail "Installer release asset is missing: $asset"
  done

  log "Installing versioned production compose and ingress assets"
  mkdir -p "$INGRESS_CONFIG_DIR" "$RUNTIME_SCRIPTS_DIR"
  install -m 0644 "$compose_asset" "$COMPOSE_FILE.tmp"
  mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
  install -m 0644 "$preflight_asset" "$RUNTIME_SCRIPTS_DIR/production-ingress-spki.mjs"
  install -m 0755 "$entrypoint_asset" "$RUNTIME_SCRIPTS_DIR/production-ingress-entrypoint.sh"
  install -m 0644 "$haproxy_asset" "$INGRESS_CONFIG_DIR/haproxy.cfg.template"
}

write_identity_generator() {
  cat >"$IDENTITY_SCRIPT.tmp" <<'NODE'
#!/usr/bin/env node
import {
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  randomBytes
} from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const scalarOrder = BigInt('0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001');
const pkcs8SeedPrefix = Buffer.from('302e020100300506032b657004220420', 'hex');
const spkiPublicPrefix = Buffer.from('302a300506032b6570032100', 'hex');

function normalizeHex(value, name) {
  const hex = value.trim().replace(/^0x/i, '').toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(hex)) {
    throw new Error(`${name} must be 32 bytes hex.`);
  }
  return hex;
}

function newBlsScalarHex() {
  for (;;) {
    const bytes = randomBytes(32);
    const scalar = BigInt(`0x${bytes.toString('hex')}`);
    if (scalar > 0n && scalar < scalarOrder) {
      return bytes.toString('hex');
    }
  }
}

function newUuidV4() {
  const bytes = randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20)
  ].join('-');
}

function requireDerPrefix(der, prefix, name) {
  if (der.length !== prefix.length + 32 || !der.subarray(0, prefix.length).equals(prefix)) {
    throw new Error(`Unexpected Ed25519 ${name} DER shape; cannot safely extract raw key bytes.`);
  }
  return der.subarray(prefix.length).toString('hex');
}

function newEd25519SeedHex() {
  const { privateKey } = generateKeyPairSync('ed25519');
  const privateDer = Buffer.from(privateKey.export({ type: 'pkcs8', format: 'der' }));
  return requireDerPrefix(privateDer, pkcs8SeedPrefix, 'private key');
}

function ed25519PublicFromSeed(seedHex) {
  const seed = Buffer.from(seedHex, 'hex');
  const privateDer = Buffer.concat([pkcs8SeedPrefix, seed]);
  const privateKey = createPrivateKey({ key: privateDer, format: 'der', type: 'pkcs8' });
  const publicKey = createPublicKey(privateKey);
  const publicDer = Buffer.from(publicKey.export({ type: 'spki', format: 'der' }));
  return requireDerPrefix(publicDer, spkiPublicPrefix, 'public key');
}

const argv = process.argv.slice(2);
const args = new Set(argv.map((item) => item.toLowerCase()));
function getArgValue(...names) {
  const normalizedNames = new Set(names.map((name) => name.toLowerCase()));
  for (let i = 0; i < argv.length; i++) {
    if (normalizedNames.has(argv[i].toLowerCase())) {
      const value = argv[i + 1];
      if (!value || value.startsWith('-')) {
        throw new Error(`${argv[i]} requires a value.`);
      }
      return value;
    }
  }
  return '';
}

const outDir = getArgValue('--out-dir', '-outdir');
if (!outDir) {
  throw new Error('--out-dir is required.');
}

const directory = resolve(outDir);
mkdirSync(directory, { recursive: true, mode: 0o700 });

const ed25519Path = resolve(directory, 'key_ed25519');
const blsPath = resolve(directory, 'key_bls');
const x25519Path = resolve(directory, 'key_x25519');
const vlessClientIdPath = resolve(directory, 'vless-client-id');
const ed25519PrivateKey = existsSync(ed25519Path)
  ? normalizeHex(readFileSync(ed25519Path, 'utf8'), 'key_ed25519')
  : newEd25519SeedHex();
const blsPrivateKey = existsSync(blsPath)
  ? normalizeHex(readFileSync(blsPath, 'utf8'), 'key_bls')
  : newBlsScalarHex();
const x25519PrivateKey = existsSync(x25519Path)
  ? normalizeHex(readFileSync(x25519Path, 'utf8'), 'key_x25519')
  : randomBytes(32).toString('hex');
if (x25519PrivateKey === ed25519PrivateKey || /^0+$/.test(x25519PrivateKey)) {
  throw new Error('key_x25519 must be nonzero and independent from key_ed25519.');
}
const vlessClientId = existsSync(vlessClientIdPath)
  ? readFileSync(vlessClientIdPath, 'utf8').trim().toLowerCase()
  : newUuidV4();
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(vlessClientId)) {
  throw new Error('vless-client-id must contain a canonical UUIDv4.');
}

writeFileSync(ed25519Path, `0x${ed25519PrivateKey}\n`, { mode: 0o600 });
writeFileSync(blsPath, `0x${blsPrivateKey}\n`, { mode: 0o600 });
writeFileSync(x25519Path, `${x25519PrivateKey}\n`, { mode: 0o600 });
writeFileSync(vlessClientIdPath, `${vlessClientId}\n`, { mode: 0o600 });

const output = {
  DEEP_NODE_ED25519_PUBLIC_KEY: ed25519PublicFromSeed(ed25519PrivateKey),
  DEEP_NODE_ED25519_PRIVATE_KEY_FILE: './secrets/key_ed25519',
  DEEP_NODE_BLS_PRIVATE_KEY_FILE: './secrets/key_bls',
  DEEP_NODE_X25519_PRIVATE_KEY_FILE: './secrets/key_x25519',
  DEEP_NODE_VLESS_CLIENT_ID_FILE: './secrets/vless-client-id'
};

if (args.has('--as-env') || args.has('-asenv')) {
  for (const [key, value] of Object.entries(output)) {
    console.log(`${key}=${value}`);
  }
} else {
  console.log(JSON.stringify(output, null, 2));
}
NODE
  mv "$IDENTITY_SCRIPT.tmp" "$IDENTITY_SCRIPT"
  chmod 700 "$IDENTITY_SCRIPT"
}

write_env_template_if_missing() {
  if [ -f "$ENV_FILE" ]; then
    return
  fi

  local environment_asset="$SCRIPT_DIR/assets/.env.node.prod.example"
  [ -f "$environment_asset" ] || fail "Installer environment asset is missing."
  log "Creating $ENV_FILE"
  install -m 0600 "$environment_asset" "$ENV_FILE"
}

env_get() {
  local key="$1"
  if [ ! -f "$ENV_FILE" ]; then
    return 0
  fi
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '\r' || true
}

env_set() {
  local key="$1"
  local value="$2"
  value="${value//$'\r'/}"
  value="${value%%$'\n'*}"
  touch "$ENV_FILE"
  if grep -q -E "^${key}=" "$ENV_FILE"; then
    local tmp
    tmp="${ENV_FILE}.tmp.$$"
    awk -v env_key="$key" -v env_value="$value" '
      index($0, env_key "=") == 1 {
        print env_key "=" env_value
        replaced = 1
        next
      }
      { print }
      END {
        if (!replaced) {
          print env_key "=" env_value
        }
      }
    ' "$ENV_FILE" >"$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
}

env_unset() {
  local key="$1"
  [ -f "$ENV_FILE" ] || return 0
  local tmp
  tmp="${ENV_FILE}.tmp.$$"
  awk -v env_key="$key" 'index($0, env_key "=") != 1 { print }' "$ENV_FILE" >"$tmp"
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

is_zero_address() {
  [[ "$1" =~ ^0x0{40}$ ]]
}

is_placeholder() {
  local value="${1:-}"
  [ -z "$value" ] && return 0
  [[ "$value" == replace_with* ]] && return 0
  [[ "$value" == *example.com* ]] && return 0
  [[ "$value" == *"<"*">"* ]] && return 0
  [[ "$value" == "0123456789abcdef" ]] && return 0
  is_zero_address "$value" && return 0
  return 1
}

is_ipv4() {
  local value="$1"
  local -a octets
  local octet

  IFS=. read -r -a octets <<<"$value"
  [ "${#octets[@]}" -eq 4 ] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    [ "$((10#$octet))" -le 255 ] || return 1
  done
}

is_public_ipv4() {
  local value="$1"
  local a b c d
  is_ipv4 "$value" || return 1
  IFS=. read -r a b c d <<<"$value"
  a=$((10#$a)); b=$((10#$b)); c=$((10#$c)); d=$((10#$d))

  [ "$a" -ne 0 ] || return 1
  [ "$a" -ne 10 ] || return 1
  [ "$a" -ne 127 ] || return 1
  [ "$a" -lt 224 ] || return 1
  ! { [ "$a" -eq 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ]; } || return 1
  ! { [ "$a" -eq 169 ] && [ "$b" -eq 254 ]; } || return 1
  ! { [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; } || return 1
  ! { [ "$a" -eq 192 ] && [ "$b" -eq 0 ] && { [ "$c" -eq 0 ] || [ "$c" -eq 2 ]; }; } || return 1
  ! { [ "$a" -eq 192 ] && [ "$b" -eq 88 ] && [ "$c" -eq 99 ]; } || return 1
  ! { [ "$a" -eq 192 ] && [ "$b" -eq 168 ]; } || return 1
  ! { [ "$a" -eq 198 ] && { [ "$b" -eq 18 ] || [ "$b" -eq 19 ]; }; } || return 1
  ! { [ "$a" -eq 198 ] && [ "$b" -eq 51 ] && [ "$c" -eq 100 ]; } || return 1
  ! { [ "$a" -eq 203 ] && [ "$b" -eq 0 ] && [ "$c" -eq 113 ]; } || return 1
}

resolve_host_public_ipv4() {
  local host="$1"
  local candidate
  [ -n "$host" ] || return 1

  if is_public_ipv4 "$host"; then
    printf '%s' "$host"
    return
  fi
  command_exists getent || return 1

  while read -r candidate _; do
    if is_public_ipv4 "$candidate"; then
      printf '%s' "$candidate"
      return
    fi
  done < <(getent ahostsv4 "$host" 2>/dev/null || true)
  return 1
}

detect_external_public_ipv4() {
  local endpoint candidate
  for endpoint in https://checkip.amazonaws.com https://api.ipify.org; do
    candidate="$(curl -4 --proto '=https' --tlsv1.2 -fsS \
      --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null \
      | tr -d '[:space:]' || true)"
    if is_public_ipv4 "$candidate"; then
      printf '%s' "$candidate"
      return
    fi
  done
  return 1
}

detect_node_public_ipv4() {
  local configured_ip configured_host candidate
  configured_ip="$(env_get DEEP_NODE_PUBLIC_IP)"
  configured_host="$(env_get DEEP_NODE_PUBLIC_HOST)"

  if is_public_ipv4 "$configured_ip"; then
    printf '%s' "$configured_ip"
    return
  fi
  if candidate="$(detect_external_public_ipv4)"; then
    printf '%s' "$candidate"
    return
  fi
  if candidate="$(resolve_host_public_ipv4 "$configured_host")"; then
    printf '%s' "$candidate"
    return
  fi
  return 1
}

detect_public_host() {
  local host
  if host="$(detect_external_public_ipv4)"; then
    printf '%s' "$host"
    return
  fi

  host="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
  case "$host" in
    ""|localhost|localhost.localdomain) printf 'node.example.invalid' ;;
    *) printf '%s' "$host" ;;
  esac
}

default_scanner_addr() {
  local public_ipv4
  if ! public_ipv4="$(detect_node_public_ipv4)"; then
    warn "Could not determine the node public IPv4 for the Reality SNI scan. Use --scanner-addr explicitly."
    return 1
  fi

  log "Using node public IPv4 as the Reality SNI scan origin: $public_ipv4"
  printf '%s' "$public_ipv4"
}

prompt_env() {
  local key="$1"
  local label="$2"
  local default_value="$3"
  local explicit_value="${4:-}"
  local current
  current="$(env_get "$key")"

  if [ -n "$explicit_value" ]; then
    env_set "$key" "$explicit_value"
    return
  fi

  if ! is_placeholder "$current"; then
    return
  fi

  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    env_set "$key" "$default_value"
    return
  fi

  local answer
  read -r -p "$label [$default_value]: " answer
  env_set "$key" "${answer:-$default_value}"
}

is_tcp_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

is_positive_integer() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

is_docker_log_max_size() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*([kKmMgG])?$ ]]
}

require_docker_log_options() {
  local max_size="$1"
  local max_file="$2"

  is_docker_log_max_size "$max_size" \
    || fail "DEEP_DOCKER_LOG_MAX_SIZE must be a positive Docker json-file size like 50m, 1g, or 1048576."
  is_positive_integer "$max_file" \
    || fail "DEEP_DOCKER_LOG_MAX_FILE must be a positive integer."
}

is_canonical_hex32() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]] && ! [[ "$1" =~ ^0{64}$ ]]
}

is_canonical_hex16() {
  [[ "$1" =~ ^[0-9a-f]{32}$ ]] && ! [[ "$1" =~ ^0{32}$ ]]
}

configure_topology() {
  local receive_position current
  receive_position="$RECEIVE_POSITION_ARG"
  if [ -z "$receive_position" ]; then
    receive_position="$(env_get DEEP_NODE_ONION_RECEIVE_POSITION)"
  fi
  case "$receive_position" in
    Ingress|Core|Exit) env_set DEEP_NODE_ONION_RECEIVE_POSITION "$receive_position" ;;
    "") ;;
    *) fail "--receive-position must be Ingress, Core, or Exit." ;;
  esac

  [ "${#PEER_ARGS[@]}" -eq 0 ] || [ "${#PEER_ARGS[@]}" -eq 2 ] \
    || fail "Specify --peer exactly twice for the three-router production topology."
  local index=1 spec router_id base_url current_pin next_pin extra
  for spec in "${PEER_ARGS[@]}"; do
    IFS=, read -r router_id base_url current_pin next_pin extra <<<"$spec"
    [ -z "${extra:-}" ] && is_canonical_hex32 "$router_id" \
      || fail "Peer $index router ID must be canonical lowercase 32-byte hex."
    [[ "$base_url" =~ ^https://[^/?#]+/$ ]] \
      || fail "Peer $index base URL must be a canonical HTTPS origin ending in /."
    is_canonical_hex32 "$current_pin" \
      || fail "Peer $index current SPKI pin must be canonical lowercase SHA-256 hex."
    is_canonical_hex32 "$next_pin" \
      || fail "Peer $index next SPKI pin must be canonical lowercase SHA-256 hex."
    [ "$current_pin" != "$next_pin" ] \
      || fail "Peer $index current and next SPKI pins must be distinct."
    env_set "DEEP_PRIVACY_PEER_${index}_ROUTER_ID" "$router_id"
    env_set "DEEP_PRIVACY_PEER_${index}_BASE_URL" "$base_url"
    env_set "DEEP_PRIVACY_PEER_${index}_CURRENT_SPKI_SHA256" "$current_pin"
    env_set "DEEP_PRIVACY_PEER_${index}_NEXT_SPKI_SHA256" "$next_pin"
    index=$((index + 1))
  done
}

prompt_port_env() {
  local key="$1"
  local label="$2"
  local default_value="$3"
  local explicit_value="${4:-}"
  local current
  current="$(env_get "$key")"

  if [ -n "$explicit_value" ]; then
    is_tcp_port "$explicit_value" || fail "$key must be a TCP port from 1 to 65535."
    env_set "$key" "$explicit_value"
    return
  fi

  if ! is_placeholder "$current"; then
    is_tcp_port "$current" || fail "$key must be a TCP port from 1 to 65535."
    return
  fi

  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    env_set "$key" "$default_value"
    return
  fi

  local answer value
  read -r -p "$label [$default_value]: " answer
  value="${answer:-$default_value}"
  is_tcp_port "$value" || fail "$key must be a TCP port from 1 to 65535."
  env_set "$key" "$value"
}

configure_env() {
  local public_host_default public_ipv4 peer_port
  public_host_default="$(detect_public_host)"

  prompt_env XNODE_IMAGE "XPoint node image" "$DEFAULT_XNODE_IMAGE" "$XNODE_IMAGE_ARG"
  prompt_env DEEP_STORAGE_SERVICE_IMAGE "Storage service image" "$DEFAULT_STORAGE_IMAGE" "$STORAGE_IMAGE_ARG"
  prompt_env DEEP_NODE_PUBLIC_HOST "Public host for this node" "$public_host_default" "$PUBLIC_HOST_ARG"
  prompt_port_env DEEP_NODE_PUBLIC_PORT "Public VLESS Reality port" "443" "$PUBLIC_PORT_ARG"
  prompt_port_env DEEP_NODE_PEER_RPC_PORT "Public signed node-to-node RPC port" "22020" "$PEER_RPC_PORT_ARG"
  prompt_env DEEP_REGISTRY_URL "Registry API URL" "$DEFAULT_REGISTRY_URL" "$REGISTRY_URL_ARG"
  prompt_env DEEP_STAKING_BACKEND_URL "Staking backend API URL" "$DEFAULT_STAKING_BACKEND_URL" "$STAKING_BACKEND_URL_ARG"
  prompt_env DEEP_OPERATOR_ADDRESS "Staking operator wallet" "0x0000000000000000000000000000000000000000" "$OPERATOR_ADDRESS_ARG"

  local operator_value
  operator_value="$(env_get DEEP_OPERATOR_ADDRESS)"
  prompt_env DEEP_REWARDS_ADDRESS "Rewards wallet" "$operator_value" "$REWARDS_ADDRESS_ARG"
  prompt_env DEEP_ARBITRUM_RPC_URL "Arbitrum One RPC URL" "$DEFAULT_ARBITRUM_RPC_URL" "$RPC_URL_ARG"
  prompt_env DEEP_ARBITRUM_FALLBACK_RPC_URLS "Fallback Arbitrum One RPC URLs" "$DEFAULT_ARBITRUM_RPC_URL" "$FALLBACK_RPC_URLS_ARG"

  env_set DEEP_SERVICE_NODE_REWARDS_ADDRESS "$PROD_SERVICE_NODE_REWARDS"
  env_set DEEP_ARBITRUM_CHAIN_ID "42161"
  env_set DEEP_NETWORK "mainnet"
  env_set DEEP_XPOINT_NETWORK_ID_HEX "$(env_get DEEP_XPOINT_NETWORK_ID_HEX | grep -E '.+' || printf '%s' "$DEFAULT_XPOINT_NETWORK_ID_HEX")"
  env_set DEEP_XPOINT_GENESIS_PIN_HEX "$(env_get DEEP_XPOINT_GENESIS_PIN_HEX | grep -E '.+' || printf '%s' "$DEFAULT_XPOINT_GENESIS_PIN_HEX")"
  env_set DEEP_XPOINT_DIRECTORY_LEAF_KEY_HEX "$(env_get DEEP_XPOINT_DIRECTORY_LEAF_KEY_HEX | grep -E '.+' || printf '%s' "$DEFAULT_XPOINT_DIRECTORY_LEAF_KEY_HEX")"
  env_set DEEP_INGRESS_CERTIFICATE_PROFILE "$CERTIFICATE_PROFILE"
  env_set DEEP_INGRESS_HOST "$(env_get DEEP_NODE_PUBLIC_HOST)"
  env_set DEEP_INGRESS_HTTPS_BIND "$(env_get DEEP_NODE_PUBLIC_PORT)"
  env_set DEEP_QUORUM_COORDINATOR_CIDR "$(env_get DEEP_QUORUM_COORDINATOR_CIDR | grep -E '.+' || printf '111.235.151.150/32')"
  env_unset DEEP_NODE_RPC_ENDPOINT
  if ! public_ipv4="$(detect_node_public_ipv4)"; then
    fail "Could not determine this node's public IPv4. Set DEEP_NODE_PUBLIC_IP in $ENV_FILE and rerun the installer."
  fi
  env_set DEEP_NODE_PUBLIC_IP "$public_ipv4"
  peer_port="$(env_get DEEP_NODE_PEER_RPC_PORT)"
  env_set DEEP_NODE_PEER_RPC_BIND "$peer_port"
  env_set DEEP_NODE_PEER_RPC_ENDPOINT "http://${public_ipv4}:${peer_port}/api/peer/onion"
  if [ -n "$PUBLIC_PORT_ARG" ]; then
    env_set DEEP_NODE_VLESS_BIND "$PUBLIC_PORT_ARG"
  else
    env_set DEEP_NODE_VLESS_BIND "$(env_get DEEP_NODE_VLESS_BIND | grep -E '.+' || env_get DEEP_NODE_PUBLIC_PORT)"
  fi
  env_set DEEP_NODE_API_BIND "$(env_get DEEP_NODE_API_BIND | grep -E '.+' || printf '127.0.0.1:8080')"
  env_set DEEP_NODE_STORAGE_BIND "$(env_get DEEP_NODE_STORAGE_BIND | grep -E '.+' || printf '127.0.0.1:22021')"
  env_set DEEP_STORAGE_RPC_URL "$(env_get DEEP_STORAGE_RPC_URL | grep -E '.+' || printf 'http://storage-service:8080')"
  env_set DEEP_PUSH_NOTIFY_URL "$(env_get DEEP_PUSH_NOTIFY_URL | grep -E '.+' || printf '%s' "$DEFAULT_PUSH_NOTIFY_URL")"
  env_set DEEP_REGISTRY_HEARTBEAT_INTERVAL "$(env_get DEEP_REGISTRY_HEARTBEAT_INTERVAL | grep -E '.+' || printf '00:00:30')"
  env_set DEEP_ENFORCE_QUORUM_SIGNING_POLICY "$(env_get DEEP_ENFORCE_QUORUM_SIGNING_POLICY | grep -E '.+' || printf 'true')"
  env_set DEEP_QUORUM_POLICY_BACKEND_TIMEOUT_SECONDS "$(env_get DEEP_QUORUM_POLICY_BACKEND_TIMEOUT_SECONDS | grep -E '.+' || printf '%s' "$DEFAULT_QUORUM_POLICY_TIMEOUT_SECONDS")"
  env_set DEEP_MAX_REWARD_SIGNATURE_INCREASE_ATOMIC "$(env_get DEEP_MAX_REWARD_SIGNATURE_INCREASE_ATOMIC | grep -E '.+' || printf '%s' "$DEFAULT_MAX_REWARD_SIGNATURE_INCREASE_ATOMIC")"
  env_set DEEP_MAX_QUORUM_SIGNATURE_TIMESTAMP_SKEW_SECONDS "$(env_get DEEP_MAX_QUORUM_SIGNATURE_TIMESTAMP_SKEW_SECONDS | grep -E '.+' || printf '%s' "$DEFAULT_QUORUM_SIGNATURE_TIMESTAMP_SKEW_SECONDS")"
  if [ -n "$DOCKER_LOG_MAX_SIZE_ARG" ]; then
    env_set DEEP_DOCKER_LOG_MAX_SIZE "$DOCKER_LOG_MAX_SIZE_ARG"
  else
    env_set DEEP_DOCKER_LOG_MAX_SIZE "$(env_get DEEP_DOCKER_LOG_MAX_SIZE | grep -E '.+' || printf '%s' "$DEFAULT_DOCKER_LOG_MAX_SIZE")"
  fi
  if [ -n "$DOCKER_LOG_MAX_FILE_ARG" ]; then
    env_set DEEP_DOCKER_LOG_MAX_FILE "$DOCKER_LOG_MAX_FILE_ARG"
  else
    env_set DEEP_DOCKER_LOG_MAX_FILE "$(env_get DEEP_DOCKER_LOG_MAX_FILE | grep -E '.+' || printf '%s' "$DEFAULT_DOCKER_LOG_MAX_FILE")"
  fi
  require_docker_log_options "$(env_get DEEP_DOCKER_LOG_MAX_SIZE)" "$(env_get DEEP_DOCKER_LOG_MAX_FILE)"
  env_set DEEP_OPERATOR_FEE_BPS "$(env_get DEEP_OPERATOR_FEE_BPS | grep -E '.+' || printf '0')"
  configure_topology
}

parse_identity_output() {
  local output="$1"
  local key="$2"
  printf '%s\n' "$output" | grep -E "^${key}=" | tail -n 1 | cut -d= -f2-
}

write_secret_text() {
  local path="$1"
  local value="$2"
  umask 077
  printf '%s\n' "$value" >"$path.tmp.$$"
  mv "$path.tmp.$$" "$path"
  chmod 600 "$path"
}

migrate_inline_transport_secrets() {
  local inline_vless inline_reality file_value
  local vless_path="$SECRETS_DIR/vless-client-id"
  local reality_path="$SECRETS_DIR/reality-private-key"
  inline_vless="$(env_get DEEP_NODE_VLESS_CLIENT_ID)"
  inline_reality="$(env_get DEEP_NODE_REALITY_PRIVATE_KEY)"

  if [ -n "$inline_vless" ] && ! is_placeholder "$inline_vless"; then
    [[ "${inline_vless,,}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] \
      || fail "Legacy DEEP_NODE_VLESS_CLIENT_ID is not a canonical UUIDv4."
    if [ -f "$vless_path" ]; then
      file_value="$(tr -d '\r\n' <"$vless_path")"
      [ "${file_value,,}" = "${inline_vless,,}" ] \
        || fail "Inline and file-backed VLESS client IDs differ; refusing an ambiguous migration."
    else
      write_secret_text "$vless_path" "${inline_vless,,}"
    fi
    env_unset DEEP_NODE_VLESS_CLIENT_ID
  fi

  if [ -n "$inline_reality" ] && ! is_placeholder "$inline_reality"; then
    [[ "$inline_reality" =~ ^[A-Za-z0-9_-]{43}$ ]] \
      || fail "Legacy DEEP_NODE_REALITY_PRIVATE_KEY is not a canonical Xray X25519 key."
    if [ -f "$reality_path" ]; then
      file_value="$(tr -d '\r\n' <"$reality_path")"
      [ "$file_value" = "$inline_reality" ] \
        || fail "Inline and file-backed Reality private keys differ; refusing an ambiguous migration."
    else
      write_secret_text "$reality_path" "$inline_reality"
    fi
    env_unset DEEP_NODE_REALITY_PRIVATE_KEY
  fi

  env_set DEEP_NODE_VLESS_CLIENT_ID_FILE "./secrets/vless-client-id"
  env_set DEEP_NODE_REALITY_PRIVATE_KEY_FILE "./secrets/reality-private-key"
}

generate_identity_if_needed() {
  log "Ensuring independent Ed25519, BLS, X25519, VLESS, and ONION secrets"
  local output
  output="$(node "$IDENTITY_SCRIPT" --as-env --out-dir "$SECRETS_DIR")"
  printf '%s\n' "$output" >"$APP_DIR/identity.generated.env"
  chmod 600 "$APP_DIR/identity.generated.env" "$SECRETS_DIR/key_ed25519" "$SECRETS_DIR/key_bls" \
    "$SECRETS_DIR/key_x25519" "$SECRETS_DIR/vless-client-id"

  env_set DEEP_NODE_ED25519_PUBLIC_KEY "$(parse_identity_output "$output" DEEP_NODE_ED25519_PUBLIC_KEY)"
  env_set DEEP_NODE_ED25519_PRIVATE_KEY_FILE "./secrets/key_ed25519"
  env_set DEEP_NODE_BLS_PRIVATE_KEY_FILE "./secrets/key_bls"
  env_set DEEP_NODE_X25519_PRIVATE_KEY_FILE "./secrets/key_x25519"
  env_set DEEP_NODE_VLESS_CLIENT_ID_FILE "./secrets/vless-client-id"

  local onion_path="$SECRETS_DIR/onion-state-protection.key"
  if [ ! -e "$onion_path" ]; then
    umask 077
    openssl rand 32 >"$onion_path"
  fi
  [ -f "$onion_path" ] || fail "ONION state-protection secret is not a regular file."
  [ "$(wc -c <"$onion_path" | tr -d ' ')" = "32" ] \
    || fail "ONION state-protection secret must contain exactly 32 raw bytes."
  chmod 600 "$onion_path"
  env_set DEEP_NODE_ONION_STATE_PROTECTION_FILE "./secrets/onion-state-protection.key"
}

choose_reality_mode_if_needed() {
  if [ "$REALITY_MODE" != "prompt" ]; then
    return
  fi
  if ! is_placeholder "$(env_get DEEP_NODE_REALITY_SERVER_NAME)"; then
    return
  fi
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    REALITY_MODE="default"
    return
  fi
  local answer
  printf 'Reality SNI mode:\n'
  printf '  1) default (%s)\n' "$DEFAULT_REALITY_SNI"
  printf '  2) auto-sni with XTLS/RealiTLScanner\n'
  read -r -p "Choose mode [1]: " answer
  case "${answer:-1}" in
    2) REALITY_MODE="scan" ;;
    *) REALITY_MODE="default" ;;
  esac
}

ensure_scanner() {
  local scanner_dir="$TOOLS_DIR/RealiTLScanner"
  local scanner_bin="$scanner_dir/RealiTLScanner"

  if [ ! -d "$scanner_dir/.git" ]; then
    log "Cloning XTLS/RealiTLScanner"
    rm -rf "$scanner_dir"
    git clone --depth 1 https://github.com/XTLS/RealiTLScanner.git "$scanner_dir"
  else
    log "Updating XTLS/RealiTLScanner"
    git -C "$scanner_dir" pull --ff-only
  fi

  if [ ! -x "$scanner_bin" ]; then
    log "Building RealiTLScanner with Docker"
    "${DOCKER_CMD[@]}" run --rm \
      -v "$scanner_dir:/src" \
      -w /src \
      golang:1.26-alpine \
      sh -c 'go build -o RealiTLScanner .'
  fi

  if [ ! -x "$scanner_bin" ]; then
    warn "RealiTLScanner binary was not built."
    return 1
  fi
  printf '%s' "$scanner_bin"
}

scan_reality_sni() {
  warn "RealiTLScanner does active TLS probing. Prefer running it from an operator workstation if your provider dislikes scanning traffic."
  local scanner_bin
  if ! scanner_bin="$(ensure_scanner)"; then
    return 1
  fi
  local out_csv="$APP_DIR/reality-sni.csv"
  local scan_log="$APP_DIR/reality-sni.log"
  local scan_addr="$SCANNER_ADDR"

  if [ -n "$SCANNER_URL" ]; then
    log "Scanning Reality SNI candidates from URL: $SCANNER_URL"
    "$scanner_bin" -url "$SCANNER_URL" -out "$out_csv" -thread "$SCANNER_THREADS" -timeout "$SCANNER_TIMEOUT" >"$scan_log" 2>&1 || true
  else
    if [ -z "$scan_addr" ]; then
      scan_addr="$(default_scanner_addr)" || return 1
    fi
    if ! [[ "$SCANNER_MAX_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
      warn "Reality scanner maximum duration must be a positive integer: $SCANNER_MAX_SECONDS"
      return 1
    fi
    command_exists timeout || { warn "The timeout command is required for bounded address scanning."; return 1; }

    log "Scanning Reality SNI candidates outward from: $scan_addr (limit: ${SCANNER_MAX_SECONDS}s)"
    local scan_status=0
    local scanner_pid
    timeout --signal=TERM --kill-after=5s "$SCANNER_MAX_SECONDS" \
      "$scanner_bin" -addr "$scan_addr" -out "$out_csv" -thread "$SCANNER_THREADS" -timeout "$SCANNER_TIMEOUT" \
      >"$scan_log" 2>&1 &
    scanner_pid=$!
    while kill -0 "$scanner_pid" 2>/dev/null; do
      if [ -s "$out_csv" ] && awk 'NR > 1 { found = 1; exit } END { exit(found ? 0 : 1) }' "$out_csv"; then
        log "Reality SNI candidate found; stopping the address scan."
        kill -TERM "$scanner_pid" 2>/dev/null || true
        break
      fi
      sleep 1
    done
    wait "$scanner_pid" || scan_status=$?
    case "$scan_status" in
      0|124|137|143) ;;
      *) warn "RealiTLScanner exited with status $scan_status; attempting to use any completed results." ;;
    esac
  fi
  cat "$scan_log" >&2 || true

  local candidate=""
  if [ ! -s "$out_csv" ]; then
    :
  else
    candidate="$(awk -F, '
      NR > 1 {
        d = $9
        if (d == "") {
          d = $3
        }
        gsub(/\r/, "", d)
        gsub(/^"|"$/, "", d)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", d)
        sub(/^\*\./, "", d)
        if (d ~ /^[A-Za-z0-9.-]+$/ && d !~ /^[0-9.]+$/) {
          print d
          exit
        }
      }
    ' "$out_csv")"
  fi

  if [ -z "$candidate" ] && [ -s "$scan_log" ]; then
    candidate="$(sed -n -E 's/.*cert-domain="?([A-Za-z0-9.*-]+[.][A-Za-z0-9.-]+)"?.*/\1/p' "$scan_log" \
      | sed -E 's/^[*][.]//' \
      | head -n 1)"
  fi

  printf '%s' "$candidate"
}

ensure_reality_keys() {
  choose_reality_mode_if_needed

  local current_private current_public current_short private_path
  private_path="$SECRETS_DIR/reality-private-key"
  current_private=""
  [ ! -f "$private_path" ] || current_private="$(tr -d '\r\n' <"$private_path")"
  current_public="$(env_get DEEP_NODE_REALITY_PUBLIC_KEY)"
  current_short="$(env_get DEEP_NODE_REALITY_SHORT_ID)"

  if [ "$ROTATE_REALITY" -ne 1 ] && { [ -n "$current_private" ] || ! is_placeholder "$current_public" || ! is_placeholder "$current_short"; } \
      && { [ -z "$current_private" ] || is_placeholder "$current_public" || is_placeholder "$current_short"; }; then
    fail "Reality key material is partial. Restore the missing values or use --rotate-reality explicitly."
  fi

  if [ "$ROTATE_REALITY" -eq 1 ] || [ -z "$current_private" ]; then
    local image output private_key public_key short_id
    image="$(env_get XNODE_IMAGE)"
    log "Generating Xray Reality key pair with $image"
    if ! output="$("${DOCKER_CMD[@]}" run --rm --entrypoint xray "$image" x25519 2>&1)"; then
      printf '%s\n' "$output" >&2
      fail "Could not run xray from $image. Ensure the image exists and is accessible. If it is a private GHCR image, run 'docker login ghcr.io' with a token that has read:packages, or make the package public."
    fi
    private_key="$(printf '%s\n' "$output" | awk -F': ' '/PrivateKey|Private key/ {print $2; exit}')"
    public_key="$(printf '%s\n' "$output" | awk -F': ' '/Password [(]PublicKey[)]|PublicKey|Public key/ {print $2; exit}')"
    short_id="$(openssl rand -hex 8)"

    [ -n "$private_key" ] || fail "Could not parse Reality private key from xray output."
    [ -n "$public_key" ] || fail "Could not parse Reality public key from xray output."

    [[ "$private_key" =~ ^[A-Za-z0-9_-]{43}$ ]] || fail "Generated Reality private key has an unexpected format."
    [[ "$public_key" =~ ^[A-Za-z0-9_-]{43}$ ]] || fail "Generated Reality public key has an unexpected format."
    write_secret_text "$private_path" "$private_key"
    env_set DEEP_NODE_REALITY_PUBLIC_KEY "$public_key"
    env_set DEEP_NODE_REALITY_SHORT_ID "$short_id"
  fi

  chmod 600 "$private_path"
  env_set DEEP_NODE_REALITY_PRIVATE_KEY_FILE "./secrets/reality-private-key"
  env_unset DEEP_NODE_REALITY_PRIVATE_KEY

  local current_sni selected_sni
  current_sni="$(env_get DEEP_NODE_REALITY_SERVER_NAME)"
  selected_sni="$DEFAULT_REALITY_SNI"

  if [ "$REALITY_MODE" = "scan" ]; then
    if ! selected_sni="$(scan_reality_sni)"; then
      fail "Reality SNI scanner failed. Rerun with --default-reality or fix the scanner input and try --auto-sni again."
    fi
    if [ -z "$selected_sni" ]; then
      warn "SNI scan did not return a candidate; falling back to $DEFAULT_REALITY_SNI"
      selected_sni="$DEFAULT_REALITY_SNI"
    fi
  fi

  if [ "$ROTATE_REALITY" -eq 1 ] || is_placeholder "$current_sni" || [ "$REALITY_MODE" != "prompt" ]; then
    env_set DEEP_NODE_REALITY_SERVER_NAME "$selected_sni"
    env_set DEEP_NODE_MASK_DOMAIN "$selected_sni"
  fi

  env_set DEEP_NODE_REALITY_FINGERPRINT "$(env_get DEEP_NODE_REALITY_FINGERPRINT | grep -E '.+' || printf 'chrome')"
  env_set DEEP_NODE_REALITY_SPIDER_X "$(env_get DEEP_NODE_REALITY_SPIDER_X | grep -E '.+' || printf '/')"
}

certificate_spki_sha256() {
  openssl x509 -in "$1" -pubkey -noout \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | sha256sum | awk '{print $1}'
}

generate_self_issued_certificate() {
  local name="$1"
  local host="$2"
  local cert_path="$SECRETS_DIR/ingress/${name}.crt"
  local key_path="$SECRETS_DIR/ingress/${name}.key"
  local pin_path="$SECRETS_DIR/ingress/${name}.spki-sha256"
  local san_type="DNS"
  is_ipv4 "$host" && san_type="IP"

  local existing=0
  [ -e "$cert_path" ] && existing=$((existing + 1))
  [ -e "$key_path" ] && existing=$((existing + 1))
  [ -e "$pin_path" ] && existing=$((existing + 1))
  [ "$existing" -eq 0 ] || [ "$existing" -eq 3 ] \
    || fail "Ingress $name certificate set is partial; restore or remove the whole set."

  if [ "$existing" -eq 0 ]; then
    log "Generating $name pinned self-issued ingress certificate"
    umask 077
    env MSYS2_ARG_CONV_EXCL='/CN=' openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -sha256 -nodes \
      -days 825 -subj "/CN=$host" -addext "subjectAltName=${san_type}:$host" \
      -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
      -addext "extendedKeyUsage=serverAuth" \
      -keyout "$key_path" -out "$cert_path" >/dev/null 2>&1
    write_secret_text "$pin_path" "$(certificate_spki_sha256 "$cert_path")"
  fi

  openssl x509 -in "$cert_path" -noout -checkend 86400 >/dev/null \
    || fail "Ingress $name certificate is invalid or expires within 24 hours."
  if is_ipv4 "$host"; then
    openssl x509 -in "$cert_path" -noout -checkip "$host" >/dev/null \
      || fail "Ingress $name certificate does not cover $host."
  else
    openssl x509 -in "$cert_path" -noout -checkhost "$host" >/dev/null \
      || fail "Ingress $name certificate does not cover $host."
  fi
  [ "$(tr -d '\r\n' <"$pin_path")" = "$(certificate_spki_sha256 "$cert_path")" ] \
    || fail "Ingress $name SPKI pin does not match its certificate."
  chmod 600 "$key_path" "$cert_path" "$pin_path"
}

ensure_ingress_certificates() {
  local host
  host="$(env_get DEEP_INGRESS_HOST)"
  [ "$CERTIFICATE_PROFILE" = "pinned-self-issued" ] \
    || fail "The public installer currently supports only the pinned-self-issued certificate profile."
  mkdir -p "$SECRETS_DIR/ingress"
  chmod 700 "$SECRETS_DIR/ingress"
  generate_self_issued_certificate current "$host"
  generate_self_issued_certificate next "$host"
  [ "$(tr -d '\r\n' <"$SECRETS_DIR/ingress/current.spki-sha256")" \
    != "$(tr -d '\r\n' <"$SECRETS_DIR/ingress/next.spki-sha256")" ] \
    || fail "Ingress current and next certificates must use distinct keys."
  env_set DEEP_INGRESS_CURRENT_CERT_FILE "./secrets/ingress/current.crt"
  env_set DEEP_INGRESS_CURRENT_KEY_FILE "./secrets/ingress/current.key"
  env_set DEEP_INGRESS_CURRENT_SPKI_FILE "./secrets/ingress/current.spki-sha256"
  env_set DEEP_INGRESS_NEXT_CERT_FILE "./secrets/ingress/next.crt"
  env_set DEEP_INGRESS_NEXT_KEY_FILE "./secrets/ingress/next.key"
  env_set DEEP_INGRESS_NEXT_SPKI_FILE "./secrets/ingress/next.spki-sha256"
}

validate_address() {
  local value="$1"
  [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]] || return 1
  ! is_zero_address "$value"
}

validate_for_start() {
  local missing=()
  local key value
  for key in \
    XNODE_IMAGE \
    DEEP_STORAGE_SERVICE_IMAGE \
    DEEP_NODE_PUBLIC_HOST \
    DEEP_NODE_PUBLIC_IP \
    DEEP_NODE_PEER_RPC_PORT \
    DEEP_NODE_PEER_RPC_ENDPOINT \
    DEEP_REGISTRY_URL \
    DEEP_XPOINT_NETWORK_ID_HEX \
    DEEP_XPOINT_GENESIS_PIN_HEX \
    DEEP_XPOINT_DIRECTORY_LEAF_KEY_HEX \
    DEEP_STAKING_BACKEND_URL \
    DEEP_ARBITRUM_RPC_URL \
    DEEP_SERVICE_NODE_REWARDS_ADDRESS \
    DEEP_INGRESS_CERTIFICATE_PROFILE \
    DEEP_INGRESS_HOST \
    DEEP_INGRESS_CURRENT_CERT_FILE \
    DEEP_INGRESS_CURRENT_KEY_FILE \
    DEEP_INGRESS_CURRENT_SPKI_FILE \
    DEEP_INGRESS_NEXT_CERT_FILE \
    DEEP_INGRESS_NEXT_KEY_FILE \
    DEEP_INGRESS_NEXT_SPKI_FILE \
    DEEP_NODE_ED25519_PUBLIC_KEY \
    DEEP_NODE_ED25519_PRIVATE_KEY_FILE \
    DEEP_NODE_X25519_PRIVATE_KEY_FILE \
    DEEP_NODE_ONION_STATE_PROTECTION_FILE \
    DEEP_NODE_ONION_RECEIVE_POSITION \
    DEEP_NODE_BLS_PRIVATE_KEY_FILE \
    DEEP_NODE_VLESS_CLIENT_ID_FILE \
    DEEP_NODE_REALITY_SERVER_NAME \
    DEEP_NODE_REALITY_PUBLIC_KEY \
    DEEP_NODE_REALITY_PRIVATE_KEY_FILE \
    DEEP_NODE_REALITY_SHORT_ID; do
    value="$(env_get "$key")"
    if is_placeholder "$value"; then
      missing+=("$key")
    fi
  done

  if ! validate_address "$(env_get DEEP_OPERATOR_ADDRESS)"; then
    missing+=("DEEP_OPERATOR_ADDRESS")
  fi
  is_canonical_hex16 "$(env_get DEEP_XPOINT_NETWORK_ID_HEX)" \
    || missing+=("DEEP_XPOINT_NETWORK_ID_HEX")
  is_canonical_hex32 "$(env_get DEEP_XPOINT_GENESIS_PIN_HEX)" \
    || missing+=("DEEP_XPOINT_GENESIS_PIN_HEX")
  is_canonical_hex32 "$(env_get DEEP_XPOINT_DIRECTORY_LEAF_KEY_HEX)" \
    || missing+=("DEEP_XPOINT_DIRECTORY_LEAF_KEY_HEX")
  if ! validate_address "$(env_get DEEP_REWARDS_ADDRESS)"; then
    missing+=("DEEP_REWARDS_ADDRESS")
  fi

  if [ ! -f "$SECRETS_DIR/key_ed25519" ]; then
    missing+=("secrets/key_ed25519")
  fi
  if [ ! -f "$SECRETS_DIR/key_bls" ]; then
    missing+=("secrets/key_bls")
  fi
  for key in \
    DEEP_PRIVACY_PEER_1_ROUTER_ID DEEP_PRIVACY_PEER_1_BASE_URL \
    DEEP_PRIVACY_PEER_1_CURRENT_SPKI_SHA256 DEEP_PRIVACY_PEER_1_NEXT_SPKI_SHA256 \
    DEEP_PRIVACY_PEER_2_ROUTER_ID DEEP_PRIVACY_PEER_2_BASE_URL \
    DEEP_PRIVACY_PEER_2_CURRENT_SPKI_SHA256 DEEP_PRIVACY_PEER_2_NEXT_SPKI_SHA256; do
    value="$(env_get "$key")"
    if is_placeholder "$value"; then
      missing+=("$key")
    fi
  done
  for value in key_x25519 onion-state-protection.key vless-client-id reality-private-key \
    ingress/current.crt ingress/current.key ingress/current.spki-sha256 \
    ingress/next.crt ingress/next.key ingress/next.spki-sha256; do
    [ -f "$SECRETS_DIR/$value" ] || missing+=("secrets/$value")
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    printf '[xpoint-node] The node was prepared, but start was blocked because these values are missing or placeholder:\n' >&2
    printf '  - %s\n' "${missing[@]}" >&2
    printf '[xpoint-node] Edit %s and rerun this installer.\n' "$ENV_FILE" >&2
    exit 2
  fi

  local public_ip public_port peer_port peer_endpoint
  public_ip="$(env_get DEEP_NODE_PUBLIC_IP)"
  public_port="$(env_get DEEP_NODE_PUBLIC_PORT)"
  peer_port="$(env_get DEEP_NODE_PEER_RPC_PORT)"
  peer_endpoint="$(env_get DEEP_NODE_PEER_RPC_ENDPOINT)"
  is_public_ipv4 "$public_ip" || fail "DEEP_NODE_PUBLIC_IP must be a public IPv4 address."
  is_tcp_port "$public_port" || fail "DEEP_NODE_PUBLIC_PORT must be a TCP port from 1 to 65535."
  is_tcp_port "$peer_port" || fail "DEEP_NODE_PEER_RPC_PORT must be a TCP port from 1 to 65535."
  [ "$public_port" != "$peer_port" ] || fail "Reality and node-to-node RPC must use different public ports."
  [ "$peer_endpoint" = "http://${public_ip}:${peer_port}/api/peer/onion" ] || \
    fail "DEEP_NODE_PEER_RPC_ENDPOINT must match the generated public IP and peer port."
  case "$(env_get DEEP_NODE_ONION_RECEIVE_POSITION)" in
    Ingress|Core|Exit) ;;
    *) fail "DEEP_NODE_ONION_RECEIVE_POSITION must be Ingress, Core, or Exit." ;;
  esac
  [ -z "$(env_get DEEP_NODE_VLESS_CLIENT_ID)" ] \
    || fail "Inline DEEP_NODE_VLESS_CLIENT_ID must be migrated to a secret file."
  [ -z "$(env_get DEEP_NODE_REALITY_PRIVATE_KEY)" ] \
    || fail "Inline DEEP_NODE_REALITY_PRIVATE_KEY must be migrated to a secret file."
}

configure_firewall_if_active() {
  command_exists ufw || return 0
  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    return 0
  fi

  local reality_port
  reality_port="$(env_get DEEP_NODE_PUBLIC_PORT)"
  log "Allowing the XPoint TLS/Reality multiplexed port in active UFW"
  run_as_root ufw allow "${reality_port}/tcp" comment 'XPoint Reality transport' >/dev/null
}

local_image_exists() {
  "${DOCKER_CMD[@]}" image inspect "$1" >/dev/null 2>&1
}

capture_failed_update_diagnostics() {
  [ -n "$ROLLBACK_DIR" ] || return 0
  local diagnostics="$ROLLBACK_DIR/failed-update-diagnostics.log"
  {
    printf 'capturedUtc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' '--- compose ps ---'
    (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" \
      -f "$COMPOSE_FILE" ps --all) || true
    printf '%s\n' '--- bounded service logs ---'
    (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" \
      -f "$COMPOSE_FILE" logs --no-color --tail 200 xnode storage-service \
      ingress-preflight ingress) || true
  } >"$diagnostics" 2>&1
  chmod 600 "$diagnostics"
  warn "Bounded failed-update diagnostics were retained in the pre-update snapshot."
}

start_or_update_node() {
  if [ "$START_NODE" -ne 1 ]; then
    log "Skipping docker compose start because --no-start was used"
    return
  fi

  validate_for_start
  log "Validating compose file"
  (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet)

  log "Pulling images"
  local pull_output
  if ! pull_output="$(cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull 2>&1)"; then
    printf '%s\n' "$pull_output" >&2
    if local_image_exists "$(env_get XNODE_IMAGE)" && local_image_exists "$(env_get DEEP_STORAGE_SERVICE_IMAGE)"; then
      warn "Image pull failed, but both configured images are available locally; continuing with local images."
    else
      fail "Could not pull required images and at least one configured image is not available locally. Make the images public, run 'docker login' with registry access, or preload/build the images before rerunning."
    fi
  else
    printf '%s\n' "$pull_output"
  fi

  log "Starting or updating node"
  if ! (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --wait --wait-timeout 180); then
    capture_failed_update_diagnostics
    fail "The node failed its health gate."
  fi
  (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps)
}

rollback_failed_update() {
  local status="$1"
  trap - EXIT
  if [ "$status" -ne 0 ] && [ "$ROLLBACK_REQUIRED" -eq 1 ]; then
    if restore_preupdate_backup; then
      warn "The failed update was rolled back to the previous healthy node release."
    else
      warn "Automatic rollback failed; use the recorded pre-update snapshot before retrying."
    fi
  fi
  exit "$status"
}

main() {
  parse_args "$@"
  require_linux
  ensure_base_packages
  ensure_docker
  ensure_app_dir
  import_existing_installation
  create_preupdate_backup
  if [ -n "$ROLLBACK_DIR" ]; then
    ROLLBACK_REQUIRED=1
    trap 'rollback_failed_update $?' EXIT
  fi
  apply_staged_upgrade
  write_compose_file
  write_identity_generator
  write_env_template_if_missing
  configure_env
  configure_docker_logging
  migrate_inline_transport_secrets
  generate_identity_if_needed
  ensure_reality_keys
  ensure_ingress_certificates
  configure_firewall_if_active
  start_or_update_node
  ROLLBACK_REQUIRED=0
  prune_docker_if_requested

  log "Done. Config: $ENV_FILE"
  log "Production stake requirement is fixed by compose: $PROD_STAKE_ATOMIC atomic XPNT."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
