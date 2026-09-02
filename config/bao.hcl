ui = true

# Storage backend - using file storage for simplicity
# For production, consider using PostgreSQL, MySQL, or Consul
storage "file" {
  path = "/openbao/data"
}

# Listener configuration
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true
}

# Telemetry (optional)
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = true
}

# Default to test environment - override in docker-compose per environment
environment = "${BAO_ENV:test}"
