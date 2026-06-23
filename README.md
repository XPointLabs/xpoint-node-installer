# XPoint Production Node Installer

Public Linux installer for a production XPoint service node.

The installer is idempotent:

- installs Docker Engine and the Docker Compose plugin when missing;
- creates `/opt/xpoint-node`;
- writes the production compose file;
- creates `.env.node.prod` only if missing and preserves manual edits;
- generates Ed25519, BLS, VLESS UUID, and Xray Reality keys when missing;
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
  --public-host seed1.xpoint.network \
  --public-port 443 \
  --operator-address 0x0000000000000000000000000000000000000000 \
  --rewards-address 0x0000000000000000000000000000000000000000 \
  --default-reality
```

Use the actual operator and rewards wallet addresses. The example zero address
will not pass the start validation.

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
under `/opt/xpoint-node/tools`. By default it checks only `1.1.1.1/32`
with one narrow scanner target and writes the scan result to
`/opt/xpoint-node/reality-sni.csv`.

Custom scanner inputs:

```bash
sudo ./install-xpoint-node.sh --auto-sni --scanner-addr 1.1.1.1/32 --scanner-threads 1 --scanner-timeout 3
```

Use broad `--scanner-url` or CIDR scans carefully. They perform active TLS
probing and can create unwanted network noise on some VPS providers.

## Common Commands

```bash
cd /opt/xpoint-node
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml ps
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml logs -f --tail 200 xnode
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml pull
docker compose --env-file ./.env.node.prod -f ./docker-compose.node.prod.yml up -d
```

Do not run `docker compose down -v` unless you intentionally want to wipe local
node state and have backed up the identity files.
