# syntax=docker/dockerfile:1
FROM alpine:3.19

# OCI image metadata (Docker Hub display)
LABEL org.opencontainers.image.title="Unbound DNS Resolver"
LABEL org.opencontainers.image.description="Lightweight recursive DNS resolver with caching, built on Alpine Linux"
LABEL org.opencontainers.image.url="https://github.com/luis/unbound-docker"
LABEL org.opencontainers.image.source="https://github.com/luis/unbound-docker"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="1.20.0"

# Install Unbound and root hints
# Alpine 3.19 provides Unbound 1.20.0-r2 (newer than 1.19.3, fully compatible)
RUN apk add --no-cache \
    unbound \
    ca-certificates \
    dnssec-root \
    && update-ca-certificates

# Create directories for Unbound (package creates unbound user)
RUN mkdir -p /etc/unbound /var/lib/unbound /var/log/unbound

# Copy default configuration
COPY unbound.conf /etc/unbound/unbound.conf

# Set permissions - unbound user is created by the apk package
RUN chown -R unbound:unbound /etc/unbound /var/lib/unbound /var/log/unbound && \
    chmod 755 /etc/unbound /var/lib/unbound /var/log/unbound && \
    chmod 644 /etc/unbound/unbound.conf

# Switch to unbound user (created by apk package)
USER unbound

# Expose DNS ports (5353 = non-privileged, works without --cap-add)
EXPOSE 5353/tcp 5353/udp

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD unbound-checkconf ${UNBOUND_CONF_PATH:-/etc/unbound/unbound.conf} >/dev/null 2>&1 || exit 1

# Run Unbound in foreground (required for containers)
CMD ["unbound", "-d", "-c", "/etc/unbound/unbound.conf"]
