# XPoint Production Node Installer

Private Linux installer for a production XPoint service node.

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
git clone git@github.com:XPointLabs/xpoint-node-installer.git
cd xpoint-node-installer
sudo ./install-xpoint-node.sh \
  --public-host seed1.xpoint.network \
  --public-port 443 \
  --operator-address 0x0000000000000000000000000000000000000000 \
  --rewards-address 0x0000000000000000000000000000000000000000
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

## Public Port

The public VLESS Reality port is operator-selectable. Port `443` is the
recommended default, but the node can run on any reachable TCP port:

```bash
sudo ./install-xpoint-node.sh \
  --public-host node1.xpoint.network \
  --public-port 8443 \
  --operator-address 0x0000000000000000000000000000000000000000 \
  --rewards-address 0x0000000000000000000000000000000000000000
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
under `/opt/xpoint-node/tools`. By default it crawls public Ubuntu mirror
domains and writes the scan result to `/opt/xpoint-node/reality-sni.csv`.

Custom scanner inputs:

```bash
sudo ./install-xpoint-node.sh --auto-sni --scanner-url https://launchpad.net/ubuntu/+archivemirrors
sudo ./install-xpoint-node.sh --auto-sni --scanner-addr 1.1.1.1/32
```

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
