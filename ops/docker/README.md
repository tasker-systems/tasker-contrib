# Docker Configurations

Docker Compose configurations for local development and testing.

## Environments

| Directory | Description |
|-----------|-------------|
| `development/` | Local development with hot reload |
| `production/` | Production-like configuration |
| `observability/` | Full observability stack (Jaeger, Prometheus, Grafana) |

## Quick Start

```bash
# Development
cd development
docker-compose up -d

# With observability
cd observability
docker-compose up -d
```

## Origin

These configurations are adapted from tasker-core/docker with contrib-specific additions.
