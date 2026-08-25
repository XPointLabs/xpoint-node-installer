# XPoint Node Installer agent rules

The workspace rules in `../AGENTS.md` apply. This file contains only installer deltas.

## Owns

- Ubuntu 22.04/24.04 production-node installation and upgrade workflow.
- Generated compose/env configuration, directories, permissions and service lifecycle.
- Public address validation, Reality/TLS settings, peer transport and bounded log policy.

Runtime behavior belongs in `xnode` and service repos; canonical production topology and operator
policy belong in `deep-devops`; user-facing procedures belong in `xpoint-docs`.

## Repository rules

- Keep installation non-interactive, rerunnable and fail-closed before mutating an existing node.
- Never embed private keys, tokens, owner addresses or provider credentials in source or output.
- Preserve strict public-IP validation; reject private, loopback, carrier-grade NAT and reserved
  documentation ranges where a publicly reachable address is required.
- Generated secrets use restrictive permissions and must not be echoed.
- Do not silently replace an operator's existing Reality SNI, ports, keys or persistent volumes.
- Bound scanners, network probes and Docker logs by time/size.
- Update README and public operator docs when options, defaults, files or recovery behavior change.
- Never run the installer against a real host without explicit deployment authorization.

## Verify

```bash
bash -n ./install-xpoint-node.sh
bash ./tests/install-xpoint-node.test.sh
```

Tests must inspect generated configuration without requiring root, Docker mutation or Internet
access.
