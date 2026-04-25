# Unbound DNS Resolver

A lightweight, production-ready recursive DNS resolver with persistent cache, available on [Docker Hub](https://hub.docker.com/r/luifrancisco/unbound) and optimized for Kubernetes/k3s deployments.

## Architecture

Unbound runs as a Deployment in the `unbound` namespace with a PersistentVolumeClaim for cache storage.
```
Unbound Pod (unbound ns)
├─ Cache: 512Mi PVC (local-path)
├─ Port: 53 (with NET_BIND_SERVICE)
└─ Image: luifrancisco/unbound:latest
```

## Prerequisites

### Docker Hub (Standalone)

- Docker Engine 20.10+ (or Podman)
- No special privileges needed — runs on non-privileged port 5353

### k3s (Cluster)

- k3s cluster (tested: v1.34.6+k3s1)
- Cilium CNI in KPR mode
- `kubectl` configured with cluster access
- Internet access to pull `luifrancisco/unbound:latest` from Docker Hub

## Quick Start

### Docker (Standalone)

```bash
# Pull from Docker Hub
docker pull luifrancisco/unbound:latest

# Run (port 5353 on host)
docker run -d \
  --name unbound \
  -p 5353:5353/tcp -p 5353:5353/udp \
  -v unbound-cache:/var/lib/unbound \
  --restart unless-stopped \
  luifrancisco/unbound:latest

# Test
dig @127.0.0.1 -p 5353 google.com +short
```

**Options:**
- Map to host port 53 (requires extra capability):
  ```bash
  docker run -d --cap-add NET_BIND_SERVICE -p 53:5353 luifrancisco/unbound:latest
  ```
- Custom configuration (ACLs, ports, etc.):
  ```bash
  docker run -d \
    -v /path/to/custom-unbound.conf:/etc/unbound/unbound.conf:ro \
    -p 5353:5353 \
    luifrancisco/unbound:latest
  ```

### k3s (Cluster)

Apply all manifests in order:

```bash
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-pvc.yaml
kubectl apply -f 04-deployment.yaml
kubectl apply -f 05-service.yaml
```

Or apply the combined manifest:

```bash
kubectl apply -f k8s-deployment.yaml
kubectl apply -f k8s-service.yaml
```

**Note:** The Service (`05-service.yaml` or `k8s-service.yaml`) can be applied independently; it does not depend on deployment order with modern Kubernetes.

#### Verify Deployment

```bash
# Wait for pod to be Ready
kubectl wait --for=condition=ready pod -l app=unbound -n unbound --timeout=60s

# Check pod status
kubectl get pods -n unbound

# Check service (NodePort 30153)
kubectl get svc -n unbound

# Test DNS resolution via node IP
dig @<node-ip> -p 30153 google.com +short
dig @<node-ip> -p 30153 example.com AAAA  # IPv6 test
```

Expected output: IP addresses for the queried domain.

## Manifest Files

| File | Resource | Purpose |
|------|----------|---------|
| `01-namespace.yaml` | `Namespace` | Isolates resources in `unbound` |
| `02-configmap.yaml` | `ConfigMap` | Unbound configuration (ACLs, cache TTLs, port override to 53) |
| `03-pvc.yaml` | `PersistentVolumeClaim` | 512Mi cache storage (`local-path` storage class) |
| `04-deployment.yaml` | `Deployment` | Unbound pod with security context, initContainer for permissions |
| `05-service.yaml` | `Service` | NodePort Service (30153 → 53 TCP/UDP) |
| `k8s-deployment.yaml` | Combined | Multi-document manifest (Namespace, ConfigMap, PVC, Deployment) |
| `k8s-service.yaml` | Service | Standalone service manifest |

## Configuration

### Unbound Config (`unbound.conf` via ConfigMap)

Key settings:

- **Port**: `53` (overridden from Docker default `5353` in k3s)
- **Interfaces**: `0.0.0.0:53` (IPv4), `[::0]:53` (IPv6)
- **ACLs**: Cluster pods (`10.43.0.0/16`), device network (`10.0.0.0/8`), loopback (`127.0.0.0/8`), and IPv6 subnet (`fd00:7808:88c3:90::/64`)
- **Cache**: Max TTL 86400s (24h), min TTL 60s, negative TTL 3600s, prefetch enabled
- **Threads**: 4 worker threads
- **Logging**: Verbosity 1 (queries disabled for performance)

Edit `02-configmap.yaml` → `data.unbound.conf` to customize.

### Resource Limits

- **CPU**: 100m request / 500m limit
- **Memory**: 128Mi request / 512Mi limit
- **Cache**: 512Mi persistent volume

Adjust in `04-deployment.yaml` → `spec.template.spec.containers[0].resources`.

### Port

NodePort: **30153** (both TCP and UDP).

Change in `05-service.yaml` → `spec.ports[].nodePort`.

## Security

- Runs as non-root user (UID 100, GID 101)
- `NET_BIND_SERVICE` capability required (to bind port 53 as non-root)
- All other capabilities dropped (`ALL` → drop)
- Privilege escalation disabled
- PVC permissions fixed via initContainer (`busybox chown`)

## Troubleshooting

See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) for:
- Pod crash loops (missing `-d` flag, permission errors)
- Image pull errors (Docker Hub rate limits, network)
- ConfigMap parsing errors
- Permission denied on port 53
- PVC mount failures

## Development Workflow

### Test Locally with docker-compose

```bash
docker-compose up --build
dig @127.0.0.1 -p 5353 google.com +short
```

Uses `docker-compose.yml` (maps host port 5353 → container port 5353).

### Redeploy to k3s

Since the image is pulled directly from Docker Hub, no local build step is needed:

```bash
# Apply updates (configmaps, deployment changes)
kubectl apply -f 02-configmap.yaml
kubectl apply -f 04-deployment.yaml

# Rolling restart if only image tag changed
kubectl rollout restart deployment unbound -n unbound
kubectl rollout status deployment unbound -n unbound
```

## Cleanup

```bash
# Delete resources in order
kubectl delete -f 05-service.yaml
kubectl delete -f 04-deployment.yaml
kubectl delete -f 03-pvc.yaml
kubectl delete -f 02-configmap.yaml
kubectl delete -f 01-namespace.yaml

# Or delete the entire namespace (removes everything)
kubectl delete namespace unbound
```

## Reference

- **Unbound docs**: https://nlnetlabs.nl/documentation/unbound/
- **k3s local-path**: Rancher `local-path` provisioner (default in k3s)
- **Docker Hub**: `luifrancisco/unbound:latest`

## License

MIT — see project root for details.
