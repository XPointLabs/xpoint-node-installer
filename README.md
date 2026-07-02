# XPoint Production Node Installer

Public Linux installer for a production XPoint service node.

The installer is idempotent:

- installs Docker Engine and the Docker Compose plugin when missing;
- creates `/opt/xpoint-node`;
- writes the production compose file;
- creates `.env.node.prod` only if missing and preserves manual edits;
- generates Ed25519, BLS, VLESS UUID, and Xray Reality keys when missing;
- detects the node public IPv4 and publishes an Ed25519-authenticated peer endpoint;
- pulls the configured images and runs `docker compose up -d`;
- on repeated runs, pulls newer image tags and updates the running node.

`DEEP_STAKE_ATOMIC` is intentionally not a node operator setting. The production
staking requirement is a protocol/contract value and is fixed in the compose
file as `25,000 XPNT` (`25000000000000` atomic units).

## Quick Start

On a fresh Ubuntu 22.04/24.04 server:

```bash
git clone https://github.com/XPointLabs/xpoint-node-installer.git
cd xpoint-node-installer
sudo ./install-xpoint-node.sh \
  --public-host 203.0.113.10 \
  --public-port 443 \
  --peer-rpc-port 22020 \
  --operator-address 0x0000000000000000000000000000000000000000 \
  --rewards-address 0x0000000000000000000000000000000000000000 \
  --default-reality
```

Use the actual operator and rewards wallet addresses. The example zero address
will not pass the start validation.

A domain and an operator-managed TLS certificate are not required. Xray Reality
provides the client-facing encrypted transport, while node-to-node onion hops
use a separate Ed25519-authenticated endpoint. `--public-host` accepts either a
DNS name or the server's public IP. The installer determines and publishes the
origin IPv4 independently, so a proxied DNS record is not used for peer traffic.

The node files are placed in:

```text
/opt/xpoint-node/docker-compose.node.prod.yml
/opt/xpoint-node/.env.node.prod
/opt/xpoint-node/secrets/key_ed25519
/opt/xpoint-node/secrets/key_bls
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
clients use that advertised port for onion routing.

## Node-to-node Port

The signed peer RPC uses TCP port `22020` by default. It is intentionally
separate from the Reality listener because it has a different protocol and
access policy:

```bash
sudo ./install-xpoint-node.sh --peer-rpc-port 32020
```

The installer generates these values on every run:

```text
DEEP_NODE_PUBLIC_IP=203.0.113.10
DEEP_NODE_PEER_RPC_PORT=32020
DEEP_NODE_PEER_RPC_BIND=32020
DEEP_NODE_PEER_RPC_ENDPOINT=http://203.0.113.10:32020/api/peer/onion
```

The endpoint does not carry plaintext messages. Onion payloads remain encrypted,
and every outer request is signed by the sending node's Ed25519 identity with a
timestamp and one-time nonce. The receiver verifies current signed membership,
rejects replays, and rate-limits the listener. If UFW is already active, the
installer opens only the selected Reality and peer TCP ports; it never enables
or changes the firewall's global policy by itself.

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

The installer also mounts the generated Ed25519 node identity into the storage sidecar. Storage-triggered requests to `push.xpoint.network` are signed automatically and are accepted only while the node is active in the XPoint registry; operators do not configure a separate push credential.

Do not run `docker compose down -v` unless you intentionally want to wipe local
node state and have backed up the identity files.
