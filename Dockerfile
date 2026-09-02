FROM openbao/openbao:latest

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

# Set permissions
RUN chmod 700 /openbao/data /openbao/logs

# Expose OpenBao API port
EXPOSE 8200

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD curl -f http://localhost:8200/v1/sys/health || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["/sbin/dumb-init", "--"]

# Start OpenBao in server mode
CMD ["bao", "server", "-config=/openbao/config/bao.hcl"]
