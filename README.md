# Unbound DNS Resolver

A lightweight, production-ready recursive DNS resolver with persistent cache, available on [Docker Hub](https://hub.docker.com/r/luis/unbound) and optimized for Kubernetes/k3s deployments.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
│   Client     │────▶│  HAProxy     │────▶│   Unbound Pod    │
│              │     │10.90.0.13:53 │     │  (unbound ns)    │
└─────────────┘     └──────────────┘     └──────────────────┘
                                                  │
                                                  ▼
                                          ┌─────────────────┐
                                          │  Cache (PVC)    │
                                          │  2Gi local-path │
                                          └─────────────────┘
```

- **Deployment**: `unbound` in namespace `unbound` (1 replica)
- **Service**: NodePort 30153 (TCP/UDP 53 → container port 5353 by default, overridden to 53 via ConfigMap in k3s)
- **Image**: `luis/unbound:latest` (Docker Hub) / `unbound-custom:latest` (local build)
- **Base**: Alpine 3.19 + Unbound 1.20.0 (11.9 MB)
- **Cache**: 2Gi PVC with `local-path` storage class
- **Security**: Non-root (UID 100), `NET_BIND_SERVICE` capability (k3s only)
- **HAProxy**: Auto-configured via generator (backend: `be_unbound_30153`)

## Prerequisites

### Docker Hub (Standalone)

- Docker Engine 20.10+ (or Podman)
- No special privileges needed — runs on non-privileged port 5353

### k3s (Cluster)

- k3s cluster (tested: v1.34.6+k3s1)
- Cilium CNI in KPR mode
- `kubectl` configured with cluster access
- `podman` on the k3s master node (for building)
- HAProxy with automatic NodePort → IPv6 mapping (optional, for IPv6 access)

## Quick Start

### Docker (Standalone)

```bash
# Pull from Docker Hub
docker pull luis/unbound:latest

# Run (port 5353 on host)
docker run -d \
  --name unbound \
  -p 5353:5353/tcp -p 5353:5353/udp \
  -v unbound-cache:/var/lib/unbound \
  --restart unless-stopped \
  luis/unbound:latest

# Test
dig @127.0.0.1 -p 5353 google.com +short
```

**Options:**
- Map to host port 53 (requires extra capability):
  ```bash
  docker run -d --cap-add NET_BIND_SERVICE -p 53:5353 luis/unbound
  ```
- Custom configuration (ACLs, ports, etc.):
  ```bash
  docker run -d \
    -v /path/to/custom-unbound.conf:/etc/unbound/unbound.conf:ro \
    -p 5353:5353 \
    luis/unbound
  ```

### k3s (Cluster)

Full k3s deployment guide:

#### Build & Tag

```bash
cd ~/projects/unbound-docker
podman build -t unbound-custom:latest .
podman tag localhost/unbound-custom:latest docker.io/library/unbound-custom:latest
```

#### Import into k3s containerd

```bash
# Save to tar
podman save unbound-custom:latest -o /tmp/unbound.tar

# Import into k3s containerd (k3s uses its own isolated containerd)
sudo k3s ctr -n k8s.io images import /tmp/unbound.tar

# Verify
sudo k3s ctr -n k8s.io images list | grep unbound
```

#### Deploy to k3s

Apply all manifests in order:

```bash
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-pvc.yaml
kubectl apply -f 04-deployment.yaml
kubectl apply -f 05-service.yaml
```

Or apply the combined manifest (legacy):

```bash
kubectl apply -f k8s-deployment.yaml
```

**Note:** The Service (`05-service.yaml`) must be applied after the Deployment to avoid endpoint validation errors.

#### Verify Deployment

```bash
# Wait for pod to be Ready
kubectl wait --for=condition=ready pod -l app=unbound -n unbound --timeout=60s

# Check pod status
kubectl get pods -n unbound

# Check service
kubectl get svc -n unbound

# Wait for HAProxy to regenerate (~30–60 seconds)
sleep 30

# Test DNS resolution
dig @10.90.0.13 -p 30153 google.com +short
dig @10.90.0.13 -p 30153 example.com AAAA  # IPv6 test
```

Expected output: IP addresses for the queried domain.

## Manifest Files

| File | Resource | Purpose |
|------|----------|---------|
| `01-namespace.yaml` | `Namespace` | Isolates resources in `unbound` |
| `02-configmap.yaml` | `ConfigMap` | Unbound configuration (ACLs, cache, verbosity) |
| `03-pvc.yaml` | `PersistentVolumeClaim` | 2Gi cache storage (local-path) |
| `04-deployment.yaml` | `Deployment` | Unbound pod with security context & initContainer |
| `05-service.yaml` | `Service` (NodePort 30153) | Exposes DNS with HAProxy annotation |
| `k8s-deployment.yaml` | Combined | Legacy multi-document manifest (namespace, configmap, pvc, deployment) |
| `k8s-service.yaml` | Service | Standalone service manifest |

## Configuration

### Unbound Config (`unbound.conf`)

Key settings:

- **Port**: `5353` (default for Docker Hub; overridden to `53` in k3s via ConfigMap)
- **Interfaces**: `0.0.0.0:5353` (IPv4), `[::0]:5353` (IPv6)
- **ACLs**: Cluster pods (`10.43.0.0/16`), device network (`10.0.0.0/8`), loopback, and IPv6 subnet
- **Cache**: Max TTL 24h, min TTL 60s, prefetch enabled
- **Threads**: 4 worker threads
- **Logging**: Verbosity 1 (queries disabled for performance)

Edit `unbound.conf` locally, then rebuild and redeploy.

### Resource Limits

- **CPU**: 100m request / 500m limit
- **Memory**: 128Mi request / 512Mi limit
- **Cache**: 2Gi persistent volume

Adjust in `04-deployment.yaml` → `spec.template.spec.containers[0].resources`.

### Port

NodePort: **30153** (both TCP and UDP). Avoids conflict with AdGuard Home's default 30053.

Change in `05-service.yaml` → `spec.ports[].nodePort`.

## Security

- Runs as non-root user (UID 100, GID 101)
- `NET_BIND_SERVICE` capability required **only in k3s** (to bind port 53)
- Docker Hub users: no capabilities needed (uses port 5353)
- All other capabilities dropped (`ALL` → drop)
- Privilege escalation disabled
- PVC permissions fixed via initContainer (`busybox chown`)

## HAProxy Integration

The service annotation `haproxy.ingress.kubernetes.io/ipv6-expose: "true"` triggers the HAProxy generator (`/usr/local/bin/generate-haproxy-nodeport.py`) to create:

```
backend be_unbound_30153
    server unbound_30153 172.16.0.XX:53 check
```

The generator runs via systemd timer (~30–60s interval). After deployment, wait ~1 minute for HAProxy to pick up the new backend.

**Manual trigger** (if needed):

```bash
sudo systemctl restart generate-haproxy-nodeport.timer
# or
sudo /usr/local/bin/generate-haproxy-nodeport.py
```

## Troubleshooting

See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) for:

- Pod crash loops (missing `-d` flag, permission errors)
- ImagePullBackOff (k3s containerd import required)
- ConfigMap parsing errors (YAML block scalar vs literal)
- HAProxy backend not appearing
- Permission denied on port 53
- PVC mount failures

## Development Workflow

### Test Locally with docker-compose

```bash
docker-compose up --build
dig @127.0.0.1 -p 5353 google.com +short
```

Uses `docker-compose.yml` (maps host port 5353 → container port 5353).

### Rebuild & Redeploy

```bash
# 1. Rebuild image
podman build -t unbound-custom:latest . --no-cache

# 2. Retag
podman tag localhost/unbound-custom:latest docker.io/library/unbound-custom:latest

# 3. Save & import
podman save unbound-custom:latest -o /tmp/unbound.tar
sudo k3s ctr -n k8s.io images import /tmp/unbound.tar

# 4. Rolling restart (zero downtime)
kubectl rollout restart deployment unbound -n unbound
kubectl rollout status deployment unbound -n unbound
```

## Cleanup

```bash
kubectl delete -f 05-service.yaml
kubectl delete -f 04-deployment.yaml
kubectl delete -f 03-pvc.yaml
kubectl delete -f 02-configmap.yaml
kubectl delete -f 01-namespace.yaml

# Or delete the namespace (removes everything)
kubectl delete namespace unbound

# Remove image from k3s containerd
sudo k3s ctr -n k8s.io images remove docker.io/library/unbound-custom:latest

# Remove local tar
rm -f /tmp/unbound.tar
```

## Reference

- **Unbound docs**: https://nlnetlabs.nl/documentation/unbound/
- **k3s containerd**: `sudo k3s ctr -n k8s.io ...` (separate namespace from host)
- **Local-path PV**: Rancher `local-path` provisioner (default in k3s)
- **HAProxy generator**: `/usr/local/bin/generate-haproxy-nodeport.py` (systemd timer)

## License

MIT — see project root for details.
