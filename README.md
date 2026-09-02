# OpenBao Vault - Multi-Environment PKI Setup

This repository contains Docker configuration for OpenBao Vault with support for multiple Certificate Authority (CA) engines across three environments: **test**, **sandbox**, and **production**.

## Architecture

### PKI Engines
- **pki_pid/** - PID Provider CA (root or intermediate)
- **pki_walletprov/** - Wallet Provider CA
- **pki_access/** - Access CA
- **pki_registration/** - Registration CA

### Environments
- **Test** (port 8200) - Development and testing
- **Sandbox** (port 8201) - Staging/pre-production
- **Production** (port 8202) - Live environment

Each environment has:
- Isolated data storage
- Separate configuration
- Independent PKI hierarchy

## Prerequisites

- Docker & Docker Compose
- OpenBao CLI (optional, for management)
- curl & jq (for API calls)

## Quick Start

### 1. Build the Docker Image

```bash
docker-compose build
```

### 2. Start All Environments

```bash
docker-compose --profile all up -d
```

Or start individual environments:

```bash
# Test only
docker-compose --profile test up -d openbao-test

# Sandbox only
docker-compose --profile sandbox up -d openbao-sandbox

# Production only
docker-compose --profile prod up -d openbao-prod
```

### 3. Unseal OpenBao

Each instance needs to be unsealed on first run:

```bash
# For test environment
docker-compose exec openbao-test bao operator init
docker-compose exec openbao-test bao operator unseal

# For sandbox environment
docker-compose exec openbao-sandbox bao operator init
docker-compose exec openbao-sandbox bao operator unseal

# For production environment
docker-compose exec openbao-prod bao operator init
docker-compose exec openbao-prod bao operator unseal
```

Save the unseal keys and root token securely!

### 4. Initialize PKI Engines

```bash
# Test environment
docker-compose exec openbao-test bao secrets list

# Initialize PKI for test
./scripts/init-pki.sh test

# Initialize PKI for sandbox
./scripts/init-pki.sh sandbox

# Initialize PKI for production
./scripts/init-pki.sh prod
```

## Access Web UI

- **Test**: http://localhost:8200/ui
- **Sandbox**: http://localhost:8201/ui
- **Production**: http://localhost:8202/ui

## API Endpoints

### Get Seal Status
```bash
curl http://localhost:8200/v1/sys/seal-status
```

### List PKI Mounts
```bash
curl http://localhost:8200/v1/sys/mounts
```

### Generate Certificate (example - PID Provider)
```bash
curl -X POST http://localhost:8200/v1/pki_pid/root/generate/internal \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -d @- <<EOF
{
  "common_name": "PID Provider Root CA",
  "ttl": "87600h"
}
EOF
```

## Environment Variables

Each environment has its own `.env` file:
- `.env.test` - Test configuration
- `.env.sandbox` - Sandbox configuration
- `.env.prod` - Production configuration

## Stopping Services

```bash
# Stop all environments
docker-compose --profile all down

# Stop specific environment
docker-compose down openbao-test
```

## Persistence

Data is persisted in named volumes:
- `openbao_test_data`
- `openbao_sandbox_data`
- `openbao_prod_data`

To clean up volumes:
```bash
docker volume rm openbao_test_data openbao_sandbox_data openbao_prod_data
```

## Production Considerations

For production deployment:

1. **Use proper TLS certificates** instead of self-signed
2. **Use a robust storage backend** (PostgreSQL, MySQL, Consul) instead of file storage
3. **Configure HA setup** with multiple replicas
4. **Implement proper backup strategy** for PKI data
5. **Use environment-specific secrets management**
6. **Enable audit logging**
7. **Configure proper authentication methods** (OAuth, OIDC, etc.)

## Security Notes

- Store unseal keys and root tokens securely (use a secret management system)
- Rotate credentials regularly
- Use TLS for all communications
- Implement proper access controls and policies
- Enable audit logging for compliance
- Regular backup and disaster recovery testing

## Troubleshooting

### Container won't start
```bash
docker-compose logs openbao-test
```

### Connection refused
- Check if container is running: `docker-compose ps`
- Verify port mappings: `docker-compose port openbao-test 8200`

### PKI commands failing
- Ensure OpenBao is unsealed: `docker-compose exec openbao-test bao status`
- Check authentication token is set

## References

- [OpenBao Documentation](https://openbao.org/docs/)
- [PKI Secrets Engine](https://openbao.org/docs/secrets/pki/)
- [OpenBao CLI](https://openbao.org/docs/commands/)

## License

[Add your license here]
