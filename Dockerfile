# Pinned, not :latest - upstream removed the "file" storage backend this
# config relies on in v2.7.0 (2026-09-23), exactly as its own v2.6.2
# deprecation warning said it would. Migrating to raft storage is the real
# fix; see CLAUDE.md.
FROM openbao/openbao:2.6.2

USER root

# Install additional tools
RUN apk add --no-cache \
    curl \
    jq \
    dumb-init \
    openssl

# Create directories for different PKI mounts
RUN mkdir -p /openbao/config \
    /openbao/data \
    /openbao/logs

# Copy environment-specific configuration
COPY config/ /openbao/config/

# Set permissions. Group is root (0) and directories are group-writable so the
# image also runs under OpenShift's default `restricted` SCC, which ignores
# USER below and instead runs the container as an arbitrary UID in group 0.
RUN chown -R openbao:0 /openbao/config /openbao/data /openbao/logs && \
    chmod -R g=u /openbao/data /openbao/logs

USER openbao

# Expose OpenBao API port
EXPOSE 8200

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD curl -f http://localhost:8200/v1/sys/health || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Start OpenBao in server mode
CMD ["bao", "server", "-config=/openbao/config/bao.hcl"]
