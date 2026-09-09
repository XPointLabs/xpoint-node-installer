# XPoint Production Node Installer

Public Linux installer for a production XPoint service node.

The installer is idempotent:

- installs Docker Engine and the Docker Compose plugin when missing;
- creates `/opt/xpoint-node`;
- writes the production compose file;
- creates `.env.node.prod` only if missing and preserves manual edits;
- configures Docker `json-file` log rotation (`50m` x `5` by default);
- preserves or generates independent Ed25519, BLS, X25519, ONION-state,
  VLESS UUID, and Xray Reality secrets;
- migrates legacy inline VLESS and Reality private values to mode-`0600` files;
- generates two locally issued TLS identities whose rotating SPKI pins are the
  node-to-node trust anchors (a public CA certificate is not required);
- snapshots config, secrets, and current image identities before every update;
- pulls the configured images and requires `docker compose up --wait` to pass;
- automatically restores the snapshot and old image tags when health fails.

`DEEP_STAKE_ATOMIC` is intentionally not a node operator setting. The production
staking requirement is a protocol/contract value and is fixed in the compose
file as `25,000 XPNT` (`25000000000000` atomic units).

The node also verifies BLS quorum-signing policy against the production staking
backend before signing reward, exit, or liquidation messages. The default is
`https://staking-api.xpoint.network`; override it with `--staking-backend-url`
only when you are intentionally joining another XPoint environment.

## Quick Start

On a fresh Ubuntu 22.04/24.04 server:

```bash
git clone https://github.com/XPointLabs/xpoint-node-installer.git
cd xpoint-node-installer
sudo ./install-xpoint-node.sh \
  --public-host seed1.example.net \
  --public-port 443 \
  --receive-position Ingress \
  --peer ROUTER_ID_2,https://seed2.example.net/,CURRENT_SPKI_2,NEXT_SPKI_2 \
  --peer ROUTER_ID_3,https://seed3.example.net/,CURRENT_SPKI_3,NEXT_SPKI_3 \
  --operator-address 0x0000000000000000000000000000000000000000 \
  --rewards-address 0x0000000000000000000000000000000000000000 \
  --default-reality
```

Use the actual operator and rewards wallet addresses. The example zero address
will not pass the start validation.

A purchased domain and an operator-managed/public-CA certificate are not
required. `--public-host` accepts a DNS name or public IP. Xray Reality provides
the client-facing transport. The same public TCP port is SNI-multiplexed to the
HTTPS node API, whose locally issued certificate is authenticated by the exact
current/next SPKI pins carried in signed protocol metadata. Hostname, validity,
and pin checks remain mandatory; this is not a trust-all TLS mode.

The installer provisions the node-side capability only. As of 2026-08-30 the
current MAUI mailbox client is not yet wired to send its privacy frame through
this Reality ingress, so installing a node does not by itself provide a usable
anti-blocking messenger path or an on-prem client profile.

The node files are placed in:

```text
/opt/xpoint-node/docker-compose.node.prod.yml
/opt/xpoint-node/.env.node.prod
/opt/xpoint-node/secrets/key_ed25519
/opt/xpoint-node/secrets/key_bls
/opt/xpoint-node/secrets/key_x25519
/opt/xpoint-node/secrets/onion-state-protection.key
/opt/xpoint-node/secrets/vless-client-id
/opt/xpoint-node/secrets/reality-private-key
/opt/xpoint-node/secrets/ingress/current.{crt,key,spki-sha256}
/opt/xpoint-node/secrets/ingress/next.{crt,key,spki-sha256}
```

Manual configuration can be changed in `/opt/xpoint-node/.env.node.prod`.
Re-run the installer after editing the file.

## Image Access

The default production images are:

```text
ghcr.io/xpointlabs/xnode:latest
ghcr.io/xpointlabs/deep-storage-service:latest
```

They must be readable by the target server. For a public installer this usually
means making the GitHub Container Registry packages public. If the packages
stay private, log in on the server first with a token that has `read:packages`:

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u USERNAME --password-stdin
```

If `docker compose pull` fails but both images are already preloaded locally,
the installer continues with the local images.

## Docker Logs And Disk Use

The installer writes both host-level Docker daemon defaults and compose-level
logging settings:

```text
DEEP_DOCKER_LOG_MAX_SIZE=50m
DEEP_DOCKER_LOG_MAX_FILE=5
```

Override them with `--docker-log-max-size` and `--docker-log-max-file`.

For existing hosts, `--prune-docker` removes stopped containers, unused images,
and build cache after the node update. Docker volumes are never pruned, but
unused rollback images and cached build layers can be removed, so keep any
rollback tags you need before using it.

## Public Port

The public VLESS Reality port is operator-selectable. Port `443` is the
recommended default, but the node can run on any reachable TCP port:

```bash
sudo ./install-xpoint-node.sh \
  --public-host node1.xpoint.network \
  --public-port 8443 \
  --operator-address 0x0000000000000000000000000000000000000000 \
  --rewards-address 0x0000000000000000000000000000000000000000 \
  --default-reality
```

The installer writes both values into `/opt/xpoint-node/.env.node.prod`:

```text
DEEP_NODE_PUBLIC_PORT=8443
DEEP_NODE_VLESS_BIND=8443
```

Keep them equal unless a reverse proxy, NAT rule, or cloud load balancer maps a
different external port to the local Docker bind. The node publishes
`DEEP_NODE_PUBLIC_HOST:DEEP_NODE_PUBLIC_PORT` in signed relay contacts, and
the target masked client transport will use that advertised port. Current MAUI
mailbox releases still use a separate direct HTTPS entry origin and must not be
described as consuming this Reality port until the client-binding gate passes.

## Node-to-node topology

For the three-router production topology, each node receives one role
(`Ingress`, `Core`, or `Exit`) and exactly two peer descriptions. Each peer
description binds the peer's Ed25519 router ID, canonical HTTPS origin, and two
distinct SPKI pins. The node-to-node API and Reality share the public TLS port;
the installer does not expose a plaintext peer port. Onion payloads remain
encrypted, outer requests are Ed25519-authenticated, and replay protection is
durable across restarts. If UFW is active, the installer opens only this
multiplexed TCP port and does not alter the firewall's global policy.

The node derives its BLS quorum signer URL from this signed peer contact.
There is no operator-configurable signer URL. On production nodes the signer
route is accepted only from the XPoint staking control-plane address and is
rate-limited; other sources receive `404`.

## Reality SNI

Default Reality camouflage:

```bash
sudo ./install-xpoint-node.sh --default-reality
```

Automatic SNI selection with `XTLS/RealiTLScanner`:

```bash
sudo ./install-xpoint-node.sh --auto-sni
```

The scanner mode clones and builds `https://github.com/XTLS/RealiTLScanner`
under `/opt/xpoint-node/tools`. By default it resolves the configured
`DEEP_NODE_PUBLIC_HOST` to the node's public IPv4 and uses that address as the
origin for RealiTLScanner's outward search. If the configured host cannot be
resolved, the installer detects the node's public IPv4 over HTTPS. Address
scans stop after the first suitable candidate or after 60 seconds by default,
and results are written to `/opt/xpoint-node/reality-sni.csv`.

Custom scanner inputs:

```bash
sudo ./install-xpoint-node.sh --auto-sni --scanner-addr 203.0.113.10 --scanner-threads 8 --scanner-timeout 3 --scanner-max-seconds 90
```

`--scanner-addr` and `--scanner-url` override automatic node-IP detection. Keep
address scans bounded: a bare IP enables RealiTLScanner's outward infinite
mode, which this installer limits with `--scanner-max-seconds`; a `/32` checks
exactly one IPv4 address. Broad URL or CIDR scans perform active TLS probing and
can create unwanted network noise on some VPS providers.

## Common Commands

```bash
cd /opt/xpoint-node
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml ps
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml logs -f --tail 200 xnode
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml pull
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml up -d
```

Pre-update snapshots are stored under `/opt/xpoint-node/backups`. They do not
copy or overwrite Docker volumes. Keep them and the automatically tagged
`xpoint-rollback:*` images until the release has passed its observation window.
Use `--import-dir` only for an empty target installation; it refuses to merge
ambiguous secret sets.

The installer also mounts the generated Ed25519 node identity into the storage sidecar. Storage-triggered requests to `push.xpoint.network` are signed automatically and are accepted only while the node is active in the XPoint registry; operators do not configure a separate push credential.

Do not run `docker compose down -v` unless you intentionally want to wipe local
node state and have backed up the identity files.
