# Unbound Docker - Troubleshooting Guide

## Table of Contents
- [Quick Start](#quick-start)
- [Deployment on k3s with Cilium](#deployment-on-k3s-with-cilium)
- [Common Issues](#common-issues)
- [Debug Checklist](#debug-checklist)
- [k3s-Specific Gotchas](#k3s-specific-gotchas)

---

## Quick Start

1. Build image on hokkaido
2. Tag for k3s containerd
3. Import into k3s
4. Deploy
5. Wait for HAProxy detection
6. Test DNS

---

## Common Issues

### 1. Image Not Found / ImagePullBackOff
Cause: k3s uses separate containerd; localhost/ treated as remote registry.
Fix: Tag as docker.io/library/... and import via k3s ctr.

### 2. ConfigMap with Literal \n
Cause: --from-literal doesn't expand escapes.
Fix: Use YAML block scalar with |.

### 3. Invalid Config Directive
Cause: log-target: stderr not valid in Unbound 1.20.
Fix: Remove; rely on verbosity or stdout.

### 4. Container Exits Immediately
Cause: Unbound daemonizes without -d.
Fix: command: ["/usr/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]

### 5. PVC Permission Denied
Cause: local-path volumes are root:root; container runs as UID 100.
Fix: initContainer chown, or use emptyDir.

### 6. Operation not permitted on Port 53
Cause: Missing NET_BIND_SERVICE capability.
Fix: Add to securityContext.capabilities.

### 7. HAProxy Backend Not Created
Cause: Service missing or annotation absent.
Fix: Create NodePort Service with haproxy.ingress.kubernetes.io/ipv6-expose: "true"

### 8. HAProxy Server DOWN
Cause: Pod not Ready or capability missing.
Fix: Verify pod Ready; ensure NET_BIND_SERVICE.

---

## Debug Checklist
- Pod status, logs, describe
- Image in k3s ctr
- Deployment settings (imagePullPolicy, command, capabilities)
- Service NodePort and selector
- HAProxy config and stats
- DNS tests (via HAProxy and direct to pod)

---

## k3s-Specific Gotchas

- Use k3s ctr (not docker/podman) to inspect images
- Import images: podman save → k3s ctr images import
- Always set imagePullPolicy: Never for local images
- local-path PVCs are root-owned; use initContainer to chown

---

## File Descriptions
- Dockerfile — Alpine + Unbound 1.20, non-root UID 100
- unbound.conf — Base config (mounted via ConfigMap)
- k8s-deployment.yaml — With PVC, initContainer, security context
- k8s-service.yaml — NodePort 30153 + HAProxy annotation
- test.py — Local docker-compose validation
- build.sh, Makefile, README.md, docker-compose.yml — standard project files

---

## Support Matrix
| Component | Version |
|-----------|---------|
| k3s | v1.34.6+k3s1 |
| Cilium | v1.19.3 |
| Unbound | 1.20.0-r2 (Alpine 3.19) |
| HAProxy | 2.4.30 (Ubuntu 22.04) |
| Storage | local-path |
