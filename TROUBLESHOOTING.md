# Unbound Docker - Troubleshooting Guide

## Table of Contents
- [Quick Start](#quick-start)
- [Common Issues](#common-issues)
- [Debug Checklist](#debug-checklist)
- [k3s-Specific Gotchas](#k3s-specific-gotchas)

---

## Quick Start

1. Pull image from Docker Hub: `luifrancisco/unbound:latest`
2. Deploy manifests to k3s
3. Test DNS via NodePort 30153

---

## Common Issues

### 1. ImagePullBackOff

**Cause:** Docker Hub rate limits or network connectivity issues.

**Fix:** Verify Docker Hub image is accessible:
```bash
# Check if image can be pulled
kubectl describe pod -n unbound -l app=unbound | grep -A5 "Events"
```

If rate-limited:
- Ensure `imagePullPolicy: IfNotPresent` (cached images) or `Always` (force refresh)
- Consider using a personal access token for higher rate limits

### 2. ConfigMap YAML Formatting

**Cause:** Using `--from-literal` with escaped newlines produces invalid config.

**Fix:** Use YAML block scalar (`|`) as shown in `02-configmap.yaml`. The config must be properly indented.

### 3. Invalid Config Directive

**Cause:** Unbound version mismatch — directive not supported (e.g., `log-target: stderr` in Unbound 1.20).

**Fix:** Remove unsupported directives; check Unbound release notes.

### 4. Container Exits Immediately

**Cause:** Unbound daemonizes without `-d` flag when run as PID 1.

**Fix:** Deployment uses `command: ["/usr/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]` — verify this is intact in `04-deployment.yaml`.

### 5. PVC Permission Denied

**Cause:** `local-path` volumes are root-owned; container runs as UID 100.

**Fix:** The `volume-permissions` initContainer runs `chown -R 100:101 /var/lib/unbound`. Verify initContainer completes successfully.

### 6. Operation not permitted on Port 53

**Cause:** Missing `NET_BIND_SERVICE` capability.

**Fix:** Deployment `securityContext.capabilities.add: ["NET_BIND_SERVICE"]` must be present. Without it, Unbound cannot bind to port 53 as non-root.

### 7. NodePort Already Allocated

**Cause:** Another Service already uses NodePort 30153.

**Fix:** Check existing services:
```bash
kubectl get svc --all-namespaces | grep 30153
```
Delete conflicting service or change `05-service.yaml` `nodePort` to an unused port (30000–32767).

---

## Debug Checklist

- [ ] `kubectl get pods -n unbound` — pod is `Running` and `READY 1/1`
- [ ] `kubectl describe pod -n unbound <pod-name>` — check events for errors
- [ ] `kubectl logs -n unbound <pod-name>` — container logs show Unbound startup
- [ ] `kubectl get pvc -n unbound` — PVC status is `Bound`
- [ ] `kubectl get svc -n unbound` — Service has `30153` nodePort
- [ ] `kubectl exec -n unbound -it <pod-name> -- cat /etc/unbound/unbound.conf` — config mounted correctly
- [ ] `dig @<node-ip> -p 30153 google.com` — DNS query succeeds

---

## k3s-Specific Gotchas

- k3s uses an isolated containerd instance — `docker` or `podman` on the host cannot see k3s images
- When pulling from Docker Hub, `imagePullPolicy: IfNotPresent` is recommended; `Always` forces re-pull
- `local-path` storage provisioner creates hostPath PVs under `/var/lib/rancher/k3s/...`
- NodePort range defaults to 30000–32767; ensure port is within range
- Cilium KPR mode requires `--enable-k8s` — already configured on hokkaido
- Use `kubectl` (not `k3s kubectl`) if kubeconfig is already configured locally

---

## File Descriptions

- `Dockerfile` — Alpine + Unbound 1.20, runs as UID 100
- `unbound.conf` — Base config (overridden by ConfigMap in k3s)
- `04-deployment.yaml` — With PVC, initContainer, security context, NET_BIND_SERVICE
- `05-service.yaml` — NodePort 30153 (no HAProxy annotation)
- `k8s-deployment.yaml` — Combined multi-doc manifest (Namespace, ConfigMap, PVC, Deployment)
- `k8s-service.yaml` — Combined service manifest
- `test.py` — Local validation script
- `docker-compose.yml` — Standalone Docker testing (port 5353)

---

## Support Matrix

| Component | Version |
|-----------|---------|
| k3s | v1.34.6+k3s1 |
| Cilium | v1.19.3 |
| Unbound | 1.20.0-r2 (Alpine 3.19) |
| Storage | local-path |
| Namespace | unbound |
| NodePort | 30153 |
| PVC Size | 512Mi |
