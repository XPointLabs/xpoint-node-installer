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
test_peer_endpoint_configuration
test_existing_reality_sni_is_preserved
test_bounded_scanner_result
printf 'PASS: install-xpoint-node tests\n'
