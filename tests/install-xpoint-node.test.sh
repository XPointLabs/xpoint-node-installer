#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install-xpoint-node.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" != "$actual" ]; then
    printf 'FAIL: %s (expected %q, got %q)\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

test_ipv4_validation() (
  source "$INSTALLER"
  is_public_ipv4 93.184.216.34
  is_public_ipv4 198.51.1.1
  ! is_public_ipv4 10.0.0.1
  ! is_public_ipv4 100.64.0.1
  ! is_public_ipv4 127.0.0.1
  ! is_public_ipv4 169.254.1.1
  ! is_public_ipv4 172.16.0.1
  ! is_public_ipv4 192.88.99.1
  ! is_public_ipv4 192.168.1.1
  ! is_public_ipv4 198.51.100.1
  ! is_public_ipv4 203.0.113.1
  ! is_public_ipv4 999.1.1.1
)

test_configured_public_ip() (
  source "$INSTALLER"
  env_get() {
    case "$1" in
      DEEP_NODE_PUBLIC_IP) printf '93.184.216.34' ;;
      *) printf 'node.example.invalid' ;;
    esac
  }
  detect_external_public_ipv4() { return 1; }
  assert_eq '93.184.216.34' "$(detect_node_public_ipv4)" 'configured public IPv4'
  assert_eq '93.184.216.34' "$(default_scanner_addr)" 'automatic scanner origin'
)

test_resolved_public_host() (
  source "$INSTALLER"
  env_get() { printf 'node.example.com'; }
  resolve_host_public_ipv4() { printf '93.184.216.35'; }
  detect_external_public_ipv4() { return 1; }
  assert_eq '93.184.216.35' "$(detect_node_public_ipv4)" 'resolved public host'
)

test_external_fallback() (
  source "$INSTALLER"
  env_get() { printf 'node.example.invalid'; }
  resolve_host_public_ipv4() { return 1; }
  detect_external_public_ipv4() { printf '93.184.216.36'; }
  assert_eq '93.184.216.36' "$(detect_node_public_ipv4)" 'HTTPS public-IP fallback'
)

test_external_ip_precedes_proxied_dns() (
  source "$INSTALLER"
  env_get() {
    case "$1" in
      DEEP_NODE_PUBLIC_IP) printf '' ;;
      *) printf 'proxied.example.net' ;;
    esac
  }
  resolve_host_public_ipv4() { printf '104.16.1.1'; }
  detect_external_public_ipv4() { printf '93.184.216.36'; }
  assert_eq '93.184.216.36' "$(detect_node_public_ipv4)" 'origin IP precedes proxied DNS'
)

test_scanner_option_precedence() (
  source "$INSTALLER"
  parse_args --scanner-url https://example.com/targets --scanner-addr 93.184.216.0/24
  assert_eq '93.184.216.0/24' "$SCANNER_ADDR" 'last scanner address option wins'
  assert_eq '' "$SCANNER_URL" 'scanner address clears URL mode'

  parse_args --scanner-addr 93.184.216.0/24 --scanner-url https://example.com/targets
  assert_eq '' "$SCANNER_ADDR" 'scanner URL clears address mode'
  assert_eq 'https://example.com/targets' "$SCANNER_URL" 'last scanner URL option wins'
)

test_peer_rpc_option() (
  source "$INSTALLER"
  parse_args --peer-rpc-port 32020
  assert_eq '32020' "$PEER_RPC_PORT_ARG" 'peer RPC port option'
)

test_phase1_options() (
  source "$INSTALLER"
  parse_args \
    --staking-backend-url https://staking-api.example.com \
    --docker-log-max-size 25m \
    --docker-log-max-file 3 \
    --prune-docker
  assert_eq 'https://staking-api.example.com' "$STAKING_BACKEND_URL_ARG" 'staking backend URL option'
  assert_eq '25m' "$DOCKER_LOG_MAX_SIZE_ARG" 'Docker log max-size option'
  assert_eq '3' "$DOCKER_LOG_MAX_FILE_ARG" 'Docker log max-file option'
  assert_eq '1' "$PRUNE_DOCKER" 'Docker prune option'
)

test_topology_options() (
  source "$INSTALLER"
  local router_a router_b pin_a pin_b pin_c pin_d temp_dir
  router_a="$(printf 'a%.0s' {1..64})"
  router_b="$(printf 'b%.0s' {1..64})"
  pin_a="$(printf '1%.0s' {1..64})"
  pin_b="$(printf '2%.0s' {1..64})"
  pin_c="$(printf '3%.0s' {1..64})"
  pin_d="$(printf '4%.0s' {1..64})"
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  APP_DIR="$temp_dir"
  ENV_FILE="$temp_dir/.env.node.prod"
  parse_args --receive-position Core \
    --peer "$router_a,https://seed1.example/,${pin_a},${pin_b}" \
    --peer "$router_b,https://seed2.example/,${pin_c},${pin_d}"
  APP_DIR="$temp_dir"
  ENV_FILE="$temp_dir/.env.node.prod"
  configure_topology
  assert_eq 'Core' "$(env_get DEEP_NODE_ONION_RECEIVE_POSITION)" 'onion receive role'
  assert_eq "$router_a" "$(env_get DEEP_PRIVACY_PEER_1_ROUTER_ID)" 'first peer router'
  assert_eq 'https://seed2.example/' "$(env_get DEEP_PRIVACY_PEER_2_BASE_URL)" 'second peer URL'
)

test_inline_secret_migration_is_idempotent() (
  source "$INSTALLER"
  local temp_dir vless reality
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  APP_DIR="$temp_dir"
  ENV_FILE="$temp_dir/.env.node.prod"
  SECRETS_DIR="$temp_dir/secrets"
  mkdir -p "$SECRETS_DIR"
  vless='123e4567-e89b-42d3-a456-426614174000'
  reality='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  printf 'DEEP_NODE_VLESS_CLIENT_ID=%s\nDEEP_NODE_REALITY_PRIVATE_KEY=%s\n' "$vless" "$reality" >"$ENV_FILE"
  migrate_inline_transport_secrets
  migrate_inline_transport_secrets
  assert_eq "$vless" "$(tr -d '\r\n' <"$SECRETS_DIR/vless-client-id")" 'VLESS secret preserved'
  assert_eq "$reality" "$(tr -d '\r\n' <"$SECRETS_DIR/reality-private-key")" 'Reality secret preserved'
  assert_eq '' "$(env_get DEEP_NODE_VLESS_CLIENT_ID)" 'inline VLESS removed'
  assert_eq '' "$(env_get DEEP_NODE_REALITY_PRIVATE_KEY)" 'inline Reality removed'
)

test_env_get_accepts_crlf_staging_files() (
  source "$INSTALLER"
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  ENV_FILE="$temp_dir/.env.node.prod"
  printf 'DEEP_NODE_PUBLIC_PORT=443\r\n' >"$ENV_FILE"
  assert_eq '443' "$(env_get DEEP_NODE_PUBLIC_PORT)" 'CRLF environment value normalized'
  is_tcp_port "$(env_get DEEP_NODE_PUBLIC_PORT)"
)

test_staged_upgrade_preserves_existing_secrets() (
  source "$INSTALLER"
  local temp_dir app_dir source_dir relative
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  app_dir="$temp_dir/app"
  source_dir="$temp_dir/source"
  mkdir -p "$app_dir/secrets" "$source_dir/secrets/ingress"
  printf 'DEEP_NODE_PUBLIC_HOST=old.example\n' >"$app_dir/.env.node.prod"
  printf 'DEEP_NODE_PUBLIC_HOST=new.example\n' >"$source_dir/.env.node.prod"
  for relative in key_ed25519 key_bls key_x25519 onion-state-protection.key \
      vless-client-id reality-private-key ingress/current.crt ingress/current.key \
      ingress/current.spki-sha256 ingress/next.crt ingress/next.key \
      ingress/next.spki-sha256; do
    mkdir -p "$(dirname "$source_dir/secrets/$relative")"
    printf 'candidate-%s' "$relative" >"$source_dir/secrets/$relative"
  done
  cp "$source_dir/secrets/key_ed25519" "$app_dir/secrets/key_ed25519"
  cp "$source_dir/secrets/key_bls" "$app_dir/secrets/key_bls"

  APP_DIR="$app_dir"
  ENV_FILE="$app_dir/.env.node.prod"
  SECRETS_DIR="$app_dir/secrets"
  UPGRADE_DIR_ARG="$source_dir"
  apply_staged_upgrade

  assert_eq 'DEEP_NODE_PUBLIC_HOST=new.example' "$(cat "$ENV_FILE")" 'staged env applied'
  for relative in key_ed25519 key_bls key_x25519 onion-state-protection.key \
      vless-client-id reality-private-key ingress/current.crt ingress/current.key \
      ingress/current.spki-sha256 ingress/next.crt ingress/next.key \
      ingress/next.spki-sha256; do
    assert_eq "candidate-$relative" "$(cat "$SECRETS_DIR/$relative")" "staged secret $relative applied"
  done
)

test_staged_upgrade_rejects_secret_replacement() (
  source "$INSTALLER"
  local temp_dir app_dir source_dir relative
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  app_dir="$temp_dir/app"
  source_dir="$temp_dir/source"
  mkdir -p "$app_dir/secrets" "$source_dir/secrets/ingress"
  printf 'OLD=1\n' >"$app_dir/.env.node.prod"
  printf 'NEW=1\n' >"$source_dir/.env.node.prod"
  printf 'existing' >"$app_dir/secrets/key_ed25519"
  for relative in key_ed25519 key_bls key_x25519 onion-state-protection.key \
      vless-client-id reality-private-key ingress/current.crt ingress/current.key \
      ingress/current.spki-sha256 ingress/next.crt ingress/next.key \
      ingress/next.spki-sha256; do
    mkdir -p "$(dirname "$source_dir/secrets/$relative")"
    printf 'candidate-%s' "$relative" >"$source_dir/secrets/$relative"
  done
  APP_DIR="$app_dir"
  ENV_FILE="$app_dir/.env.node.prod"
  SECRETS_DIR="$app_dir/secrets"
  UPGRADE_DIR_ARG="$source_dir"
  if (apply_staged_upgrade >/dev/null 2>&1); then
    printf 'FAIL: staged upgrade replaced an existing secret\n' >&2
    exit 1
  fi
  assert_eq 'existing' "$(cat "$app_dir/secrets/key_ed25519")" 'existing secret retained after rejection'
)

test_failed_update_runs_rollback_handler() (
  source "$INSTALLER"
  local temp_dir marker status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  marker="$temp_dir/restored"
  status=0
  (
    ROLLBACK_REQUIRED=1
    restore_preupdate_backup() { printf 'yes' >"$marker"; }
    rollback_failed_update 23
  ) >/dev/null 2>&1 || status=$?
  assert_eq '23' "$status" 'failed update retains original exit status'
  assert_eq 'yes' "$(cat "$marker")" 'failed update invokes rollback'
)

test_failed_update_diagnostics_are_bounded() (
  source "$INSTALLER"
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  APP_DIR="$temp_dir/app"
  ENV_FILE="$APP_DIR/.env.node.prod"
  COMPOSE_FILE="$APP_DIR/docker-compose.node.prod.yml"
  ROLLBACK_DIR="$APP_DIR/backups/pre-update-test"
  COMPOSE_CMD=(fake-compose)
  mkdir -p "$ROLLBACK_DIR"
  fake-compose() {
    case "$*" in
      *' ps --all') printf 'bounded-ps\n' ;;
      *' logs --no-color --tail 200 '*) printf 'bounded-logs\n' ;;
      *) return 1 ;;
    esac
  }
  capture_failed_update_diagnostics
  grep -q '^bounded-ps$' "$ROLLBACK_DIR/failed-update-diagnostics.log"
  grep -q '^bounded-logs$' "$ROLLBACK_DIR/failed-update-diagnostics.log"
)

test_identity_and_ingress_secrets_are_stable() (
  source "$INSTALLER"
  local temp_dir first_hash second_hash
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  APP_DIR="$temp_dir"
  ENV_FILE="$temp_dir/.env.node.prod"
  SECRETS_DIR="$temp_dir/secrets"
  IDENTITY_SCRIPT="$temp_dir/new-xnode-identity.mjs"
  mkdir -p "$SECRETS_DIR"
  write_identity_generator
  generate_identity_if_needed
  first_hash="$(sha256sum "$SECRETS_DIR/key_ed25519" "$SECRETS_DIR/key_bls" "$SECRETS_DIR/key_x25519" "$SECRETS_DIR/vless-client-id")"
  generate_identity_if_needed
  second_hash="$(sha256sum "$SECRETS_DIR/key_ed25519" "$SECRETS_DIR/key_bls" "$SECRETS_DIR/key_x25519" "$SECRETS_DIR/vless-client-id")"
  assert_eq "$first_hash" "$second_hash" 'identity secrets preserved across rerun'
  assert_eq '32' "$(wc -c <"$SECRETS_DIR/onion-state-protection.key" | tr -d ' ')" 'raw ONION secret length'

  CERTIFICATE_PROFILE=pinned-self-issued
  env_set DEEP_INGRESS_HOST seed1.example
  ensure_ingress_certificates
  [ -s "$SECRETS_DIR/ingress/current.crt" ]
  [ -s "$SECRETS_DIR/ingress/next.crt" ]
  [ "$(tr -d '\r\n' <"$SECRETS_DIR/ingress/current.spki-sha256")" != \
    "$(tr -d '\r\n' <"$SECRETS_DIR/ingress/next.spki-sha256")" ]

  SECRETS_DIR="$temp_dir/ip-secrets"
  mkdir -p "$SECRETS_DIR"
  env_set DEEP_INGRESS_HOST 93.184.216.34
  ensure_ingress_certificates
  node "$ROOT_DIR/assets/scripts/production-ingress-spki.mjs" \
    --profile pinned-self-issued --host 93.184.216.34 \
    --current-cert "$SECRETS_DIR/ingress/current.crt" \
    --current-key "$SECRETS_DIR/ingress/current.key" \
    --current-pin "$SECRETS_DIR/ingress/current.spki-sha256" \
    --next-cert "$SECRETS_DIR/ingress/next.crt" \
    --next-key "$SECRETS_DIR/ingress/next.key" \
    --next-pin "$SECRETS_DIR/ingress/next.spki-sha256" \
    --client-timeout-seconds 30 --server-timeout-seconds 30 \
    --quorum-cidr 93.184.216.35/32 >/dev/null
)

test_docker_log_option_validation() (
  source "$INSTALLER"
  is_docker_log_max_size 50m
  is_docker_log_max_size 1g
  is_docker_log_max_size 1048576
  ! is_docker_log_max_size 0m
  ! is_docker_log_max_size 50mb
  ! is_docker_log_max_size invalid

  is_positive_integer 1
  is_positive_integer 5
  ! is_positive_integer 0
  ! is_positive_integer 3x
)

test_peer_endpoint_configuration() (
  source "$INSTALLER"
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  APP_DIR="$temp_dir"
  ENV_FILE="$temp_dir/.env.node.prod"
  cat >"$ENV_FILE" <<'ENV'
DEEP_NODE_PUBLIC_HOST=node.example.invalid
DEEP_NODE_PUBLIC_PORT=443
DEEP_NODE_PEER_RPC_PORT=22020
DEEP_NODE_RPC_ENDPOINT=http://127.0.0.1:8080/api/session/rpc
DEEP_OPERATOR_ADDRESS=0x1111111111111111111111111111111111111111
ENV
  NON_INTERACTIVE=1
  detect_public_host() { printf '93.184.216.34'; }
  detect_node_public_ipv4() { printf '93.184.216.34'; }
  configure_env
  assert_eq '93.184.216.34' "$(env_get DEEP_NODE_PUBLIC_IP)" 'generated public IP'
  assert_eq 'http://93.184.216.34:22020/api/peer/onion' "$(env_get DEEP_NODE_PEER_RPC_ENDPOINT)" 'generated peer endpoint'
  assert_eq '' "$(env_get DEEP_NODE_RPC_ENDPOINT)" 'legacy RPC endpoint removed'
  assert_eq 'https://staking-api.xpoint.network' "$(env_get DEEP_STAKING_BACKEND_URL)" 'default staking backend URL'
  assert_eq 'true' "$(env_get DEEP_ENFORCE_QUORUM_SIGNING_POLICY)" 'quorum policy enforcement default'
  assert_eq '5' "$(env_get DEEP_QUORUM_POLICY_BACKEND_TIMEOUT_SECONDS)" 'quorum policy timeout default'
  assert_eq '100000000000000' "$(env_get DEEP_MAX_REWARD_SIGNATURE_INCREASE_ATOMIC)" 'reward signature cap default'
  assert_eq '300' "$(env_get DEEP_MAX_QUORUM_SIGNATURE_TIMESTAMP_SKEW_SECONDS)" 'signature timestamp skew default'
  assert_eq "$DEFAULT_XPOINT_NETWORK_ID_HEX" "$(env_get DEEP_XPOINT_NETWORK_ID_HEX)" 'official network ID default'
  assert_eq "$DEFAULT_XPOINT_GENESIS_PIN_HEX" "$(env_get DEEP_XPOINT_GENESIS_PIN_HEX)" 'official genesis pin default'
  assert_eq "$DEFAULT_XPOINT_DIRECTORY_LEAF_KEY_HEX" "$(env_get DEEP_XPOINT_DIRECTORY_LEAF_KEY_HEX)" 'official directory leaf key default'
  assert_eq '50m' "$(env_get DEEP_DOCKER_LOG_MAX_SIZE)" 'Docker log max-size default'
  assert_eq '5' "$(env_get DEEP_DOCKER_LOG_MAX_FILE)" 'Docker log max-file default'
)

test_compose_contains_phase1_policy_and_logging() (
  source "$INSTALLER"
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  APP_DIR="$temp_dir"
  COMPOSE_FILE="$temp_dir/docker-compose.node.prod.yml"
  write_compose_file

  grep -q 'max-size: ${DEEP_DOCKER_LOG_MAX_SIZE:-50m}' "$COMPOSE_FILE"
  grep -q 'max-file: ${DEEP_DOCKER_LOG_MAX_FILE:-5}' "$COMPOSE_FILE"
  grep -q 'RegistryRegistration__QuorumPolicyBackendBaseUrl: ${DEEP_STAKING_BACKEND_URL:?set DEEP_STAKING_BACKEND_URL}' "$COMPOSE_FILE"
  grep -q 'RegistryRegistration__EnforceQuorumSigningPolicy: ${DEEP_ENFORCE_QUORUM_SIGNING_POLICY:-true}' "$COMPOSE_FILE"
  grep -q '^      ContactService__RuntimeActivation: "true"$' "$COMPOSE_FILE"
  grep -q '^      ContactAuthority__XPointNetworkGenesisPinHex: ${DEEP_XPOINT_GENESIS_PIN_HEX:?set DEEP_XPOINT_GENESIS_PIN_HEX}$' "$COMPOSE_FILE"
  grep -q '^      ContactRouteClosure__Enabled: "true"$' "$COMPOSE_FILE"
  grep -q '^      RequiredTerminals__Contact: "true"$' "$COMPOSE_FILE"
  grep -q '^      RequiredTerminals__GroupControl: "false"$' "$COMPOSE_FILE"
)

test_existing_reality_sni_is_preserved() (
  source "$INSTALLER"
  env_get() { printf 'cloudflare-dns.com'; }
  NON_INTERACTIVE=1
  REALITY_MODE=prompt
  choose_reality_mode_if_needed
  assert_eq 'prompt' "$REALITY_MODE" 'existing Reality SNI preserved'
)

test_bounded_scanner_result() (
  source "$INSTALLER"
  local temp_dir fake_scanner candidate
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  fake_scanner="$temp_dir/fake-scanner"

  cat >"$fake_scanner" <<'SCANNER'
#!/usr/bin/env bash
set -Eeuo pipefail
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\n' 'IP,ORIGIN,TLS,ALPN,CURVE,CERT_LENGTH,CERT_SIGNATURE,CERT_PUBLICKEY,CERT_DOMAIN,CERT_ISSUER,GEO_CODE' >"$out"
printf '%s\n' '93.184.216.35,93.184.216.35,TLS 1.3,h2,X25519,1000,ECDSA,ECDSA,*.mask.example,Example CA,US' >>"$out"
sleep 10
SCANNER
  chmod +x "$fake_scanner"

  APP_DIR="$temp_dir"
  SCANNER_ADDR="93.184.216.34"
  SCANNER_URL=""
  SCANNER_THREADS=1
  SCANNER_TIMEOUT=1
  SCANNER_MAX_SECONDS=5
  ensure_scanner() { printf '%s' "$fake_scanner"; }

  candidate="$(scan_reality_sni)"
  assert_eq 'mask.example' "$candidate" 'candidate preserved after bounded scan timeout'
)

test_ipv4_validation
test_configured_public_ip
test_resolved_public_host
test_external_fallback
test_external_ip_precedes_proxied_dns
test_scanner_option_precedence
test_peer_rpc_option
test_phase1_options
test_topology_options
test_inline_secret_migration_is_idempotent
test_env_get_accepts_crlf_staging_files
test_staged_upgrade_preserves_existing_secrets
test_staged_upgrade_rejects_secret_replacement
test_failed_update_runs_rollback_handler
test_failed_update_diagnostics_are_bounded
test_identity_and_ingress_secrets_are_stable
test_docker_log_option_validation
test_peer_endpoint_configuration
test_compose_contains_phase1_policy_and_logging
test_existing_reality_sni_is_preserved
test_bounded_scanner_result
printf 'PASS: install-xpoint-node tests\n'
