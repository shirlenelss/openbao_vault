# Getting Started

Step-by-step guide to bring up one environment (test, sandbox, or production) and generate its PKI CAs. Steps are shown for **test**; swap the profile name, service name, and port for sandbox (8201) or prod (8202).

Note: every `docker compose exec ... bao ...` call below passes `-e BAO_ADDR=http://127.0.0.1:8200` — without it, the `bao` CLI inside the container defaults to `https://127.0.0.1:8200` and fails with `server gave HTTP response to HTTPS client`, since this setup runs with TLS disabled.

## 1. Build the image

```bash
docker compose build
```

## 2. Start the container

```bash
docker compose --profile test up -d openbao-test
```

## 3. Initialize (first time only, per data volume)

This generates the unseal key(s) and root token. **Save this output somewhere safe — it's shown only once.**

```bash
docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-test bao operator init -key-shares=1 -key-threshold=1
```

Using 1 share / 1 threshold here for a simple single-key setup. Use more shares and a higher threshold for a real production deployment.

If you've already run `init` against this data volume before, skip to step 4.

Save the unseal key and root token into a gitignored env file (`.test.env` / `.sandbox.env` / `.prod.env` are already in `.gitignore`):

```bash
cat > .test.env <<EOF
BAO_UNSEAL_KEY_TEST=<unseal_key_from_step_3>
BAO_ROOT_TOKEN_TEST=<root_token_from_step_3>
EOF
```

## 4. Unseal

The container comes up sealed on every restart and needs this each time:

```bash
source .test.env
docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-test bao operator unseal "$BAO_UNSEAL_KEY_TEST"
```

## 5. Generate the PKI CAs

```bash
source .test.env
BAO_TOKEN="$BAO_ROOT_TOKEN_TEST" BAO_ADDR=http://localhost:8200 ./scripts/init-pki.sh test
```

This mounts and generates root CAs for all four engines: `pid-issuer`, `verifier-backend`, `wallet-provider`, `trust-source` (named after the [diggsweden/wallet-ecosystem](https://github.com/diggsweden/wallet-ecosystem) services they'll eventually serve). Requires the `bao` CLI installed locally. If you don't have it installed, run the script inside the container instead:

```bash
docker cp scripts/init-pki.sh openbao-test:/tmp/init-pki.sh
docker compose exec -u root openbao-test chmod 644 /tmp/init-pki.sh  # docker cp preserves host file mode; the openbao user needs read access
source .test.env
docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_ROOT_TOKEN_TEST" openbao-test sh /tmp/init-pki.sh test
```

## 6. Verify

```bash
curl http://localhost:8200/v1/sys/seal-status
open http://localhost:8200/ui   # log in with the root token
```

## Starting over

```bash
docker compose --profile test down
docker volume rm openbao_vault_openbao_test_data
```
