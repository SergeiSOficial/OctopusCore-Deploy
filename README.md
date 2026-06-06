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

## Node Metrics Agent

```sh
REMOTE_WRITE_URL=https://metrics-write.example.com/api/v1/write \
REMOTE_WRITE_PASSWORD='change-me' \
OCTOPUSCORE_NODE_ID=node-1 \
OCTOPUSCORE_NODE_REGION=eu-west \
curl -fsSL https://raw.githubusercontent.com/SergeiSOficial/OctopusCore-Deploy/main/install-node.sh | sudo -E bash
```

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
- `octopuscore-controller-ubuntu.tar.gz`
- `octopuscore-node-agent-ubuntu.tar.gz`
- `octopuscore-monitoring-ubuntu.tar.gz`
- `SHA256SUMS`
- `release-manifest.json`

Installers verify SHA256 before applying host changes.
