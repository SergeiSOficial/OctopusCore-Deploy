# OctopusCore Deploy

Binary-only deployment entrypoint for OctopusCore.

This repository is intentionally small. It contains installer scripts and release
metadata only. Compiled programs and deploy bundles are published as GitHub
Release assets.

## Main Controller

```sh
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-controller.sh | sudo bash
```

Useful options:

```sh
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-controller.sh \
  | sudo bash -s -- --version latest --bind 127.0.0.1:8088 --enable-now
```

When a controller host already has `octopuscore-dataplane-node.service`, the
controller installer upgrades that colocated role to the same release and
requires the internal Link speed service to become healthy. Use
`--no-sync-dataplane` only when the roles intentionally follow separate release
cadences.

DCP HTTPS and DCP DoH are advertised alongside the DCP UDP Gateway by default.
The controller bridges `/v1/link/dcp-https` sessions to the local dataplane
listener and serves DNS-message requests at `/dns-query`:

```sh
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-controller.sh \
  | sudo bash -s -- \
      --version latest \
      --public-dcp-gateways udp://octopus.dedyn.io:443 \
      --public-dcp-https-gateways https://octopus.dedyn.io/v1/link/dcp-https \
      --public-dcp-doh-gateways https://octopus.dedyn.io/dns-query \
      --dcp-https-upstream 127.0.0.1:443 \
      --enable-now
```

DCP DNS UDP is optional and requires an operator-owned delegated zone. It is
authoritative-only and best effort:

```sh
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-controller.sh \
  | sudo bash -s -- \
      --version latest \
      --public-dcp-dns-zones ocl.octopus.dedyn.io \
      --dcp-dns-udp-bind 0.0.0.0:53 \
      --dcp-dns-upstream 127.0.0.1:443 \
      --dcp-dns-max-query-bytes 1232 \
      --dcp-dns-max-response-bytes 1232 \
      --enable-now
```

## HTTPS Fronting

Keep the controller bound to localhost and expose only public HTTPS API paths
through Caddy. For `*.dedyn.io` names, store the deSEC dynDNS token in a
root-only file first:

```sh
printf '%s\n' '<DESEC_DYNDNS_TOKEN>' \
  | sudo install -m 0600 -o root -g root /dev/stdin /etc/octopuscore/desec-token
```

Then install or update the front:

```sh
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-fronting.sh \
  | sudo bash -s -- \
      --host octopus.dedyn.io \
      --upstream 127.0.0.1:8088 \
      --desec-domain octopus.dedyn.io \
      --desec-token-file /etc/octopuscore/desec-token \
      --desec-ip 139.185.59.24
```

## Node Metrics Agent

```sh
REMOTE_WRITE_URL=https://metrics-write.example.com/api/v1/write \
REMOTE_WRITE_PASSWORD='change-me' \
OCTOPUSCORE_NODE_ID=node-1 \
OCTOPUSCORE_NODE_REGION=eu-west \
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-node.sh | sudo -E bash
```

## Dataplane Node

For a coordinator host that should also serve as the first public DCP-v3
gateway:

```sh
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-dataplane-node.sh \
  | sudo bash -s -- --version latest --gateway octopus.dedyn.io:443 --enable-now
```

OCI ingress must allow UDP/443 to the instance.

The same host can expose DCP HTTPS and DCP DoH through the controller/fronting
path without opening another public TCP port. Keep the local dataplane listener
on `127.0.0.1:443` and advertise `https://<host>/v1/link/dcp-https` plus
`https://<host>/dns-query` with the controller installer options above.

The dataplane installer also selects and installs the bounded CLE speed service
for the host architecture. It listens only on the internal Link address at
TCP/UDP `51901` and accepts per-lease authenticated measurements. Runtime
authorization and aggregate status files remain under
`/run/octopuscore-dataplane/` with mode `0600`.

## Monitoring Server

Install files first:

```sh
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-monitoring.sh | sudo bash
```

Start when DNS and environment values are ready:

```sh
OCTOPUSCORE_GRAFANA_HOST=grafana.example.com \
OCTOPUSCORE_METRICS_WRITE_HOST=metrics-write.example.com \
GRAFANA_ADMIN_PASSWORD='change-me' \
REMOTE_WRITE_PASSWORD_HASH='paste-caddy-hash' \
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-monitoring.sh | sudo -E bash -s -- --enable-now
```

## Release Assets

Each release contains:

- `ocpd-linux-amd64`
- `ocpd-linux-arm64`
- `gotatun-linux-amd64`
- `octopuscore-speed-proof-linux-amd64`
- `octopuscore-speed-proof-linux-arm64`
- `octopuscore-controller-ubuntu.tar.gz`
- `octopuscore-dataplane-node-ubuntu.tar.gz`
- `octopuscore-node-agent-ubuntu.tar.gz`
- `octopuscore-monitoring-ubuntu.tar.gz`
- `SHA256SUMS`
- `release-manifest.json`

Installers verify SHA256 before applying host changes.

The dataplane bundle includes `service-registry.json`, `service-registry.py`,
and `verify-dataplane-services.sh`. Installation is complete only when every
required registry listener and its bounded client-pool firewall rule verify.
