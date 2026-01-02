# Operational Tooling

Infrastructure, deployment, and observability configurations for Tasker.

## Contents

| Directory | Description |
|-----------|-------------|
| `helm/` | Kubernetes Helm charts |
| `terraform/` | Cloud infrastructure modules (AWS, GCP, Azure) |
| `docker/` | Docker Compose configurations |
| `monitoring/` | Observability configurations (Grafana, Prometheus, Datadog) |

## Quick Start

### Local Development with Docker

```bash
cd ops/docker/development
docker-compose up -d
```

### Kubernetes with Helm

```bash
helm install tasker ./ops/helm/tasker-full-stack
```

## Status

📋 Planned
