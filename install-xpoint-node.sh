#!/usr/bin/env bash
set -Eeuo pipefail

INSTALLER_VERSION="0.1.0"
APP_DIR="${XPOINT_NODE_DIR:-/opt/xpoint-node}"
NON_INTERACTIVE=0
START_NODE=1
ROTATE_REALITY=0
REALITY_MODE="${XPOINT_REALITY_MODE:-prompt}"

PUBLIC_HOST_ARG=""
PUBLIC_PORT_ARG=""
OPERATOR_ADDRESS_ARG=""
REWARDS_ADDRESS_ARG=""
REGISTRY_URL_ARG=""
RPC_URL_ARG=""
FALLBACK_RPC_URLS_ARG=""
RPC_ENDPOINT_ARG=""
SIGNING_ENDPOINT_ARG=""
XNODE_IMAGE_ARG=""
STORAGE_IMAGE_ARG=""
SCANNER_ADDR="${XPOINT_REALITY_SCAN_ADDR:-}"
SCANNER_URL="${XPOINT_REALITY_SCAN_URL:-https://launchpad.net/ubuntu/+archivemirrors}"
SCANNER_THREADS="${XPOINT_REALITY_SCAN_THREADS:-16}"
SCANNER_TIMEOUT="${XPOINT_REALITY_SCAN_TIMEOUT:-5}"

PROD_STAKE_ATOMIC="25000000000000"
PROD_SERVICE_NODE_REWARDS="0xc52284b7aBAebbEF7BdE0E1ca8251B44AeA12F5f"
DEFAULT_REGISTRY_URL="https://registry.xpoint.network"
DEFAULT_PUSH_NOTIFY_URL="https://push.xpoint.network/_compat/push-notify"
DEFAULT_ARBITRUM_RPC_URL="https://arb1.arbitrum.io/rpc"
DEFAULT_XNODE_IMAGE="ghcr.io/xpointlabs/xnode:latest"
DEFAULT_STORAGE_IMAGE="ghcr.io/xpointlabs/deep-storage-service:latest"
DEFAULT_REALITY_SNI="www.microsoft.com"

COMPOSE_FILE=""
ENV_FILE=""
SECRETS_DIR=""
TOOLS_DIR=""
IDENTITY_SCRIPT=""
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
  --rpc-url URL                Arbitrum One RPC URL used by the node backend
  --fallback-rpc-urls URLS     Comma-separated fallback Arbitrum One RPC URLs
  --rpc-endpoint URL           Private/control-plane node RPC endpoint
  --signing-endpoint URL       Private/control-plane BLS signing endpoint
  --xnode-image IMAGE          XPoint node image
  --storage-image IMAGE        Per-node storage service image
  --default-reality            Use the default Reality SNI
  --auto-sni                   Select Reality SNI with XTLS/RealiTLScanner
  --scanner-url URL            URL for RealiTLScanner crawl mode
  --scanner-addr TARGET        Address/CIDR/domain for RealiTLScanner addr mode
  --scanner-threads N          Scanner worker count (default: 16)
  --scanner-timeout SECONDS    Scanner timeout (default: 5)
  --rotate-reality             Regenerate Reality keys and re-apply SNI mode
  --no-start                   Prepare files but do not run docker compose up
  -y, --yes                    Non-interactive; use defaults and fail if required values stay missing
  -h, --help                   Show this help
USAGE
}

log() {
  printf '[xpoint-node] %s\n' "$*"
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
      --rpc-url) RPC_URL_ARG="${2:?missing value for --rpc-url}"; shift 2 ;;
      --fallback-rpc-urls) FALLBACK_RPC_URLS_ARG="${2:?missing value for --fallback-rpc-urls}"; shift 2 ;;
      --rpc-endpoint) RPC_ENDPOINT_ARG="${2:?missing value for --rpc-endpoint}"; shift 2 ;;
      --signing-endpoint) SIGNING_ENDPOINT_ARG="${2:?missing value for --signing-endpoint}"; shift 2 ;;
      --xnode-image) XNODE_IMAGE_ARG="${2:?missing value for --xnode-image}"; shift 2 ;;
      --storage-image) STORAGE_IMAGE_ARG="${2:?missing value for --storage-image}"; shift 2 ;;
      --default-reality) REALITY_MODE="default"; shift ;;
      --auto-sni) REALITY_MODE="scan"; shift ;;
      --scanner-url) SCANNER_URL="${2:?missing value for --scanner-url}"; SCANNER_ADDR=""; shift 2 ;;
      --scanner-addr) SCANNER_ADDR="${2:?missing value for --scanner-addr}"; shift 2 ;;
      --scanner-threads) SCANNER_THREADS="${2:?missing value for --scanner-threads}"; shift 2 ;;
      --scanner-timeout) SCANNER_TIMEOUT="${2:?missing value for --scanner-timeout}"; shift 2 ;;
      --rotate-reality) ROTATE_REALITY=1; shift ;;
      --no-start) START_NODE=0; shift ;;
      -y|--yes) NON_INTERACTIVE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  COMPOSE_FILE="$APP_DIR/docker-compose.node.prod.yml"
  ENV_FILE="$APP_DIR/.env.node.prod"
  SECRETS_DIR="$APP_DIR/secrets"
  TOOLS_DIR="$APP_DIR/tools"
  IDENTITY_SCRIPT="$APP_DIR/new-xnode-identity.mjs"
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
    fail "Only apt-based Linux distributions are automated for now. Install Docker, curl, openssl, git, nodejs, and npm manually, then rerun."
  fi

  log "Installing base packages if missing"
  run_as_root apt-get update
  run_as_root apt-get install -y ca-certificates curl gnupg openssl git nodejs npm
}

ensure_docker() {
  if command_exists docker && docker compose version >/dev/null 2>&1; then
    log "Docker and Docker Compose are already installed"
  else
    log "Installing Docker Engine and Compose plugin"
    run_as_root install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | run_as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      run_as_root chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
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

ensure_app_dir() {
  log "Preparing $APP_DIR"
  run_as_root mkdir -p "$APP_DIR" "$SECRETS_DIR" "$TOOLS_DIR"
  if [ "$(id -u)" -ne 0 ]; then
    run_as_root chown -R "$(id -u):$(id -g)" "$APP_DIR"
  fi
  chmod 700 "$SECRETS_DIR"
}

write_compose_file() {
  log "Writing production compose file"
  cat >"$COMPOSE_FILE.tmp" <<'YAML'
name: xpoint-node-prod

services:
  xnode:
    image: ${XNODE_IMAGE:?set XNODE_IMAGE}
    restart: unless-stopped
    stop_grace_period: 30s
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://0.0.0.0:8080

      Node__ApiListenUrl: http://0.0.0.0:8080
      Node__DataDirectory: /var/lib/xnode
      Node__RouterId: ${DEEP_NODE_ED25519_PUBLIC_KEY:?set DEEP_NODE_ED25519_PUBLIC_KEY}
      Node__Ed25519PrivateKeyPath: /run/secrets/node-ed25519-private-key
      Node__IsRelay: "true"
      Node__Network: ${DEEP_NETWORK:-mainnet}
      Node__PublicHost: ${DEEP_NODE_PUBLIC_HOST:?set DEEP_NODE_PUBLIC_HOST}
      Node__PublicPort: ${DEEP_NODE_PUBLIC_PORT:-443}
      Node__PublicRpcEndpoint: ${DEEP_NODE_RPC_ENDPOINT:?set DEEP_NODE_RPC_ENDPOINT}

      Runtime__BootstrapFromStorage: ${DEEP_NODE_BOOTSTRAP_FROM_STORAGE:-true}
      Runtime__HeartbeatInterval: ${DEEP_NODE_RUNTIME_HEARTBEAT_INTERVAL:-00:00:30}
      Runtime__RequireSignedRelayContacts: "true"

      RegistryBootstrap__BaseUrl: ${DEEP_REGISTRY_URL:?set DEEP_REGISTRY_URL}
      StorageRpc__BaseUrl: ${DEEP_STORAGE_RPC_URL:?set DEEP_STORAGE_RPC_URL}

      Vless__Enabled: "true"
      Vless__MockProcess: "false"
      Vless__XrayExecutablePath: /usr/local/bin/xray
      Vless__GeneratedConfigPath: /etc/xnode/xray.generated.json
      Vless__WorkingDirectory: /var/lib/xnode/xray
      Vless__InboundListenHost: 0.0.0.0
      Vless__InboundListenPort: ${DEEP_NODE_VLESS_CONTAINER_PORT:-443}
      Vless__PublicHost: ${DEEP_NODE_PUBLIC_HOST:?set DEEP_NODE_PUBLIC_HOST}
      Vless__PublicPort: ${DEEP_NODE_PUBLIC_PORT:-443}
      Vless__ApiIngressHost: 127.0.0.1
      Vless__ApiIngressPort: "8080"
      Vless__ClientId: ${DEEP_NODE_VLESS_CLIENT_ID:?set DEEP_NODE_VLESS_CLIENT_ID}
      Vless__MaskDomain: ${DEEP_NODE_MASK_DOMAIN:-www.microsoft.com}
      Vless__TransportMode: Reality
      Vless__Reality__ServerName: ${DEEP_NODE_REALITY_SERVER_NAME:-www.microsoft.com}
      Vless__Reality__PublicKey: ${DEEP_NODE_REALITY_PUBLIC_KEY:?set DEEP_NODE_REALITY_PUBLIC_KEY}
      Vless__Reality__PrivateKey: ${DEEP_NODE_REALITY_PRIVATE_KEY:?set DEEP_NODE_REALITY_PRIVATE_KEY}
      Vless__Reality__ShortId: ${DEEP_NODE_REALITY_SHORT_ID:?set DEEP_NODE_REALITY_SHORT_ID}
      Vless__Reality__Fingerprint: ${DEEP_NODE_REALITY_FINGERPRINT:-chrome}
      Vless__Reality__SpiderX: ${DEEP_NODE_REALITY_SPIDER_X:-/}

      RegistryHeartbeat__Enabled: "true"
      RegistryHeartbeat__Endpoint: ${DEEP_REGISTRY_URL:?set DEEP_REGISTRY_URL}/api/nodes/register
      RegistryHeartbeat__Interval: ${DEEP_REGISTRY_HEARTBEAT_INTERVAL:-00:00:30}

      RegistryRegistration__OperatorAddress: ${DEEP_OPERATOR_ADDRESS:?set DEEP_OPERATOR_ADDRESS}
      RegistryRegistration__RewardsAddress: ${DEEP_REWARDS_ADDRESS:?set DEEP_REWARDS_ADDRESS}
      RegistryRegistration__OperatorFeeBps: ${DEEP_OPERATOR_FEE_BPS:-0}
      RegistryRegistration__StakeAtomic: "25000000000000"
      RegistryRegistration__ChainId: ${DEEP_ARBITRUM_CHAIN_ID:-42161}
      RegistryRegistration__Ed25519PublicKey: ${DEEP_NODE_ED25519_PUBLIC_KEY:?set DEEP_NODE_ED25519_PUBLIC_KEY}
      RegistryRegistration__Ed25519Signature: ${DEEP_NODE_ED25519_SIGNATURE:-}
      RegistryRegistration__BlsPrivateKeyPath: /run/secrets/node-bls-private-key
      RegistryRegistration__EthereumRpcUrl: ${DEEP_ARBITRUM_RPC_URL:-https://arb1.arbitrum.io/rpc}
      RegistryRegistration__EthereumFallbackRpcUrls: ${DEEP_ARBITRUM_FALLBACK_RPC_URLS:-https://arb1.arbitrum.io/rpc}
      RegistryRegistration__ServiceNodeRewardsAddress: ${DEEP_SERVICE_NODE_REWARDS_ADDRESS:?set DEEP_SERVICE_NODE_REWARDS_ADDRESS}
      RegistryRegistration__SigningEndpoint: ${DEEP_NODE_SIGNING_ENDPOINT:?set DEEP_NODE_SIGNING_ENDPOINT}
    ports:
      - "${DEEP_NODE_VLESS_BIND:-443}:${DEEP_NODE_VLESS_CONTAINER_PORT:-443}"
      - "${DEEP_NODE_API_BIND:-127.0.0.1:8080}:8080"
    volumes:
      - xnode-state:/var/lib/xnode
      - xnode-config:/etc/xnode
    secrets:
      - source: node-ed25519-private-key
        target: node-ed25519-private-key
      - source: node-bls-private-key
        target: node-bls-private-key
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/health/ready >/dev/null"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  storage-service:
    image: ${DEEP_STORAGE_SERVICE_IMAGE:?set DEEP_STORAGE_SERVICE_IMAGE}
    restart: unless-stopped
    environment:
      PORT: "8080"
      SERVICE_NAME: deep-storage-service
      COMPAT_STATE_DIR: /var/lib/deep/storage-service
      PUSH_COMPAT_NOTIFY_URL: ${DEEP_PUSH_NOTIFY_URL:-}
    ports:
      - "${DEEP_NODE_STORAGE_BIND:-127.0.0.1:22021}:8080"
    volumes:
      - node-storage-state:/var/lib/deep/storage-service
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:8080/health/ready').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 10s

volumes:
  xnode-state:
  xnode-config:
  node-storage-state:

secrets:
  node-ed25519-private-key:
    file: ${DEEP_NODE_ED25519_PRIVATE_KEY_FILE:?set DEEP_NODE_ED25519_PRIVATE_KEY_FILE}
  node-bls-private-key:
    file: ${DEEP_NODE_BLS_PRIVATE_KEY_FILE:?set DEEP_NODE_BLS_PRIVATE_KEY_FILE}
YAML
  mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
}

write_identity_generator() {
  cat >"$IDENTITY_SCRIPT.tmp" <<'NODE'
#!/usr/bin/env node
import {
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  randomBytes,
  randomUUID
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
const ed25519PrivateKey = existsSync(ed25519Path)
  ? normalizeHex(readFileSync(ed25519Path, 'utf8'), 'key_ed25519')
  : newEd25519SeedHex();
const blsPrivateKey = existsSync(blsPath)
  ? normalizeHex(readFileSync(blsPath, 'utf8'), 'key_bls')
  : newBlsScalarHex();

writeFileSync(ed25519Path, `0x${ed25519PrivateKey}\n`, { mode: 0o600 });
writeFileSync(blsPath, `0x${blsPrivateKey}\n`, { mode: 0o600 });

const output = {
  DEEP_NODE_ED25519_PUBLIC_KEY: ed25519PublicFromSeed(ed25519PrivateKey),
  DEEP_NODE_ED25519_PRIVATE_KEY_FILE: './secrets/key_ed25519',
  DEEP_NODE_BLS_PRIVATE_KEY_FILE: './secrets/key_bls',
  DEEP_NODE_VLESS_CLIENT_ID: randomUUID()
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

  log "Creating $ENV_FILE"
  cat >"$ENV_FILE" <<ENV
XNODE_IMAGE=$DEFAULT_XNODE_IMAGE
DEEP_STORAGE_SERVICE_IMAGE=$DEFAULT_STORAGE_IMAGE
DEEP_NETWORK=mainnet

DEEP_NODE_PUBLIC_HOST=
DEEP_NODE_PUBLIC_PORT=443
DEEP_NODE_VLESS_BIND=443
DEEP_NODE_API_BIND=127.0.0.1:8080
DEEP_NODE_STORAGE_BIND=127.0.0.1:22021
DEEP_NODE_RPC_ENDPOINT=http://127.0.0.1:8080/api/session/rpc
DEEP_NODE_SIGNING_ENDPOINT=http://127.0.0.1:8080/api/staking/quorum/sign
DEEP_STORAGE_RPC_URL=http://storage-service:8080
DEEP_PUSH_NOTIFY_URL=$DEFAULT_PUSH_NOTIFY_URL

DEEP_REGISTRY_URL=$DEFAULT_REGISTRY_URL
DEEP_REGISTRY_HEARTBEAT_INTERVAL=00:00:30

DEEP_OPERATOR_ADDRESS=0x0000000000000000000000000000000000000000
DEEP_REWARDS_ADDRESS=0x0000000000000000000000000000000000000000
DEEP_OPERATOR_FEE_BPS=0

DEEP_ARBITRUM_RPC_URL=$DEFAULT_ARBITRUM_RPC_URL
DEEP_ARBITRUM_FALLBACK_RPC_URLS=$DEFAULT_ARBITRUM_RPC_URL
DEEP_ARBITRUM_CHAIN_ID=42161
DEEP_SERVICE_NODE_REWARDS_ADDRESS=$PROD_SERVICE_NODE_REWARDS

DEEP_NODE_ED25519_PUBLIC_KEY=
DEEP_NODE_ED25519_PRIVATE_KEY_FILE=./secrets/key_ed25519
DEEP_NODE_ED25519_SIGNATURE=
DEEP_NODE_BLS_PRIVATE_KEY_FILE=./secrets/key_bls

DEEP_NODE_VLESS_CLIENT_ID=
DEEP_NODE_MASK_DOMAIN=$DEFAULT_REALITY_SNI
DEEP_NODE_REALITY_SERVER_NAME=$DEFAULT_REALITY_SNI
DEEP_NODE_REALITY_PUBLIC_KEY=
DEEP_NODE_REALITY_PRIVATE_KEY=
DEEP_NODE_REALITY_SHORT_ID=
DEEP_NODE_REALITY_FINGERPRINT=chrome
DEEP_NODE_REALITY_SPIDER_X=/
ENV
  chmod 600 "$ENV_FILE"
}

env_get() {
  local key="$1"
  if [ ! -f "$ENV_FILE" ]; then
    return 0
  fi
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true
}

sed_escape_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

env_set() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="$(sed_escape_replacement "$value")"
  touch "$ENV_FILE"
  if grep -q -E "^${key}=" "$ENV_FILE"; then
    sed -i.bak -E "s|^${key}=.*|${key}=${escaped}|" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
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

detect_public_host() {
  local host
  host="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
  case "$host" in
    ""|localhost|localhost.localdomain) printf 'node.example.invalid' ;;
    *) printf '%s' "$host" ;;
  esac
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
  local public_host_default
  public_host_default="$(detect_public_host)"

  prompt_env XNODE_IMAGE "XPoint node image" "$DEFAULT_XNODE_IMAGE" "$XNODE_IMAGE_ARG"
  prompt_env DEEP_STORAGE_SERVICE_IMAGE "Storage service image" "$DEFAULT_STORAGE_IMAGE" "$STORAGE_IMAGE_ARG"
  prompt_env DEEP_NODE_PUBLIC_HOST "Public host for this node" "$public_host_default" "$PUBLIC_HOST_ARG"
  prompt_port_env DEEP_NODE_PUBLIC_PORT "Public VLESS Reality port" "443" "$PUBLIC_PORT_ARG"
  prompt_env DEEP_REGISTRY_URL "Registry API URL" "$DEFAULT_REGISTRY_URL" "$REGISTRY_URL_ARG"
  prompt_env DEEP_OPERATOR_ADDRESS "Staking operator wallet" "0x0000000000000000000000000000000000000000" "$OPERATOR_ADDRESS_ARG"

  local operator_value
  operator_value="$(env_get DEEP_OPERATOR_ADDRESS)"
  prompt_env DEEP_REWARDS_ADDRESS "Rewards wallet" "$operator_value" "$REWARDS_ADDRESS_ARG"
  prompt_env DEEP_ARBITRUM_RPC_URL "Arbitrum One RPC URL" "$DEFAULT_ARBITRUM_RPC_URL" "$RPC_URL_ARG"
  prompt_env DEEP_ARBITRUM_FALLBACK_RPC_URLS "Fallback Arbitrum One RPC URLs" "$DEFAULT_ARBITRUM_RPC_URL" "$FALLBACK_RPC_URLS_ARG"
  prompt_env DEEP_NODE_RPC_ENDPOINT "Control-plane RPC endpoint" "http://127.0.0.1:8080/api/session/rpc" "$RPC_ENDPOINT_ARG"
  prompt_env DEEP_NODE_SIGNING_ENDPOINT "Control-plane BLS signing endpoint" "http://127.0.0.1:8080/api/staking/quorum/sign" "$SIGNING_ENDPOINT_ARG"

  env_set DEEP_SERVICE_NODE_REWARDS_ADDRESS "$PROD_SERVICE_NODE_REWARDS"
  env_set DEEP_ARBITRUM_CHAIN_ID "42161"
  env_set DEEP_NETWORK "mainnet"
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
  env_set DEEP_OPERATOR_FEE_BPS "$(env_get DEEP_OPERATOR_FEE_BPS | grep -E '.+' || printf '0')"
}

parse_identity_output() {
  local output="$1"
  local key="$2"
  printf '%s\n' "$output" | grep -E "^${key}=" | tail -n 1 | cut -d= -f2-
}

generate_identity_if_needed() {
  log "Ensuring node Ed25519/BLS identity"
  local output
  output="$(node "$IDENTITY_SCRIPT" --as-env --out-dir "$SECRETS_DIR")"
  printf '%s\n' "$output" >"$APP_DIR/identity.generated.env"
  chmod 600 "$APP_DIR/identity.generated.env" "$SECRETS_DIR/key_ed25519" "$SECRETS_DIR/key_bls"

  env_set DEEP_NODE_ED25519_PUBLIC_KEY "$(parse_identity_output "$output" DEEP_NODE_ED25519_PUBLIC_KEY)"
  env_set DEEP_NODE_ED25519_PRIVATE_KEY_FILE "./secrets/key_ed25519"
  env_set DEEP_NODE_BLS_PRIVATE_KEY_FILE "./secrets/key_bls"

  local current_vless
  current_vless="$(env_get DEEP_NODE_VLESS_CLIENT_ID)"
  if is_placeholder "$current_vless"; then
    env_set DEEP_NODE_VLESS_CLIENT_ID "$(parse_identity_output "$output" DEEP_NODE_VLESS_CLIENT_ID)"
  fi
}

choose_reality_mode_if_needed() {
  if [ "$REALITY_MODE" != "prompt" ]; then
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
      golang:1.22-alpine \
      sh -lc 'go build -o RealiTLScanner .'
  fi

  [ -x "$scanner_bin" ] || fail "RealiTLScanner binary was not built."
  printf '%s' "$scanner_bin"
}

scan_reality_sni() {
  warn "RealiTLScanner does active TLS probing. Prefer running it from an operator workstation if your provider dislikes scanning traffic."
  local scanner_bin
  scanner_bin="$(ensure_scanner)"
  local out_csv="$APP_DIR/reality-sni.csv"

  if [ -n "$SCANNER_ADDR" ]; then
    log "Scanning Reality SNI candidates from address target: $SCANNER_ADDR"
    "$scanner_bin" -addr "$SCANNER_ADDR" -out "$out_csv" -thread "$SCANNER_THREADS" -timeout "$SCANNER_TIMEOUT" || true
  else
    log "Scanning Reality SNI candidates from URL: $SCANNER_URL"
    "$scanner_bin" -url "$SCANNER_URL" -out "$out_csv" -thread "$SCANNER_THREADS" -timeout "$SCANNER_TIMEOUT" || true
  fi

  if [ ! -s "$out_csv" ]; then
    return 1
  fi

  awk -F, '
    NR > 1 {
      d = $9
      if (d == "") {
        d = $3
      }
      gsub(/^"|"$/, "", d)
      sub(/^\*\./, "", d)
      if (d ~ /^[A-Za-z0-9.-]+$/ && d !~ /^[0-9.]+$/) {
        print d
        exit
      }
    }
  ' "$out_csv"
}

ensure_reality_keys() {
  choose_reality_mode_if_needed

  local current_private current_public current_short
  current_private="$(env_get DEEP_NODE_REALITY_PRIVATE_KEY)"
  current_public="$(env_get DEEP_NODE_REALITY_PUBLIC_KEY)"
  current_short="$(env_get DEEP_NODE_REALITY_SHORT_ID)"

  if [ "$ROTATE_REALITY" -eq 1 ] || is_placeholder "$current_private" || is_placeholder "$current_public" || is_placeholder "$current_short"; then
    local image output private_key public_key short_id
    image="$(env_get XNODE_IMAGE)"
    log "Generating Xray Reality key pair with $image"
    output="$("${DOCKER_CMD[@]}" run --rm --entrypoint xray "$image" x25519)"
    private_key="$(printf '%s\n' "$output" | awk -F': ' '/Private key/ {print $2; exit}')"
    public_key="$(printf '%s\n' "$output" | awk -F': ' '/Public key/ {print $2; exit}')"
    short_id="$(openssl rand -hex 8)"

    [ -n "$private_key" ] || fail "Could not parse Reality private key from xray output."
    [ -n "$public_key" ] || fail "Could not parse Reality public key from xray output."

    env_set DEEP_NODE_REALITY_PRIVATE_KEY "$private_key"
    env_set DEEP_NODE_REALITY_PUBLIC_KEY "$public_key"
    env_set DEEP_NODE_REALITY_SHORT_ID "$short_id"
  fi

  local current_sni selected_sni
  current_sni="$(env_get DEEP_NODE_REALITY_SERVER_NAME)"
  selected_sni="$DEFAULT_REALITY_SNI"

  if [ "$REALITY_MODE" = "scan" ]; then
    selected_sni="$(scan_reality_sni || true)"
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
    DEEP_NODE_RPC_ENDPOINT \
    DEEP_NODE_SIGNING_ENDPOINT \
    DEEP_REGISTRY_URL \
    DEEP_ARBITRUM_RPC_URL \
    DEEP_SERVICE_NODE_REWARDS_ADDRESS \
    DEEP_NODE_ED25519_PUBLIC_KEY \
    DEEP_NODE_ED25519_PRIVATE_KEY_FILE \
    DEEP_NODE_BLS_PRIVATE_KEY_FILE \
    DEEP_NODE_VLESS_CLIENT_ID \
    DEEP_NODE_REALITY_SERVER_NAME \
    DEEP_NODE_REALITY_PUBLIC_KEY \
    DEEP_NODE_REALITY_PRIVATE_KEY \
    DEEP_NODE_REALITY_SHORT_ID; do
    value="$(env_get "$key")"
    if is_placeholder "$value"; then
      missing+=("$key")
    fi
  done

  if ! validate_address "$(env_get DEEP_OPERATOR_ADDRESS)"; then
    missing+=("DEEP_OPERATOR_ADDRESS")
  fi
  if ! validate_address "$(env_get DEEP_REWARDS_ADDRESS)"; then
    missing+=("DEEP_REWARDS_ADDRESS")
  fi

  if [ ! -f "$SECRETS_DIR/key_ed25519" ]; then
    missing+=("secrets/key_ed25519")
  fi
  if [ ! -f "$SECRETS_DIR/key_bls" ]; then
    missing+=("secrets/key_bls")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    printf '[xpoint-node] The node was prepared, but start was blocked because these values are missing or placeholder:\n' >&2
    printf '  - %s\n' "${missing[@]}" >&2
    printf '[xpoint-node] Edit %s and rerun this installer.\n' "$ENV_FILE" >&2
    exit 2
  fi

  local rpc_endpoint signing_endpoint
  rpc_endpoint="$(env_get DEEP_NODE_RPC_ENDPOINT)"
  signing_endpoint="$(env_get DEEP_NODE_SIGNING_ENDPOINT)"
  case "$rpc_endpoint $signing_endpoint" in
    *127.0.0.1*|*localhost*)
      warn "Control-plane endpoints point to localhost. This is fine only if registry/staking reach the node through a private proxy or local deployment."
      ;;
  esac
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
  (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull)

  log "Starting or updating node"
  (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d)
  (cd "$APP_DIR" && "${COMPOSE_CMD[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps)
}

main() {
  parse_args "$@"
  require_linux
  ensure_base_packages
  ensure_docker
  ensure_app_dir
  write_compose_file
  write_identity_generator
  write_env_template_if_missing
  configure_env
  generate_identity_if_needed
  ensure_reality_keys
  start_or_update_node

  log "Done. Config: $ENV_FILE"
  log "Production stake requirement is fixed by compose: $PROD_STAKE_ATOMIC atomic XPNT."
}

main "$@"
