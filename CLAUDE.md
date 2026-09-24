# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Docker configuration for running [OpenBao](https://openbao.org/) (a Vault fork) as three isolated environments — test, sandbox, production — each hosting four PKI (certificate authority) secrets engines, one per service in the [diggsweden/wallet-ecosystem](https://github.com/diggsweden/wallet-ecosystem) EUDI wallet reference stack: `pid-issuer`, `verifier-backend`, `wallet-provider`, `trust-source`. These mount paths and the EC P-256 key type are chosen to mirror that ecosystem's real certificate profile (see `config/certificates/` and `config/certificates/scripts/generate_keystores.sh` in that repo) — the intent is that these OpenBao PKI engines become the actual cert issuer for those microservices when deployed to an OpenShift/Kubernetes cluster, replacing the reference repo's static locally-generated dev certs. Deliberately **not** matched: the reference profile's eIDAS QC statement extensions (custom ASN.1 OIDs, `organizationIdentifier`) — Vault/OpenBao's PKI `issue` API can't emit those; doing so would need generating the CSR ourselves and using `sign-verbatim` instead.

There is no application code here — this is infrastructure config (Dockerfile, docker-compose.yml, HCL config, a shell script, and OpenShift/Kustomize manifests).

## Commands

```bash
# Build the image (shared by all three environments)
docker compose build

# Start one environment (profiles: test, sandbox, prod, all)
docker compose --profile test up -d openbao-test
docker compose --profile all up -d          # all three at once

# Logs / status
docker compose logs openbao-test
docker compose ps

# First-run unseal (required before the API/UI is usable)
docker compose exec openbao-test bao operator init
docker compose exec openbao-test bao operator unseal

# Stop
docker compose --profile all down
```

OpenShift/Kubernetes (Kustomize base + per-environment overlays in `openshift/`; validate rendering without a cluster via `kubectl kustomize`):
```bash
kubectl kustomize openshift/overlays/test   # or sandbox / prod — sanity-check before applying

# Namespace isn't created by kustomize itself, and the token Secret must
# exist before the Deployment does:
oc new-project openbao-test   # or: kubectl create ns openbao-test
oc create secret generic openbao-token --from-literal=token=<vault-token> -n openbao-test
oc apply -k openshift/overlays/test
```
Both Dockerfiles (`Dockerfile`, `pki-cert-client/Dockerfile`) are built to also run correctly under OpenShift's default `restricted` SCC (arbitrary UID, group 0) — see the Architecture section below. Image references in `openshift/base/kustomization.yaml` are placeholders (`REPLACE_WITH_YOUR_REGISTRY/...`); there's no CI/registry push pipeline in this repo yet, so images must be built and pushed manually before applying.

PKI init script (mounts each PKI engine if needed, tunes max lease TTL, generates its root CA, sets CRL/issuing URLs):
```bash
BAO_TOKEN=<root_token> BAO_ADDR=http://localhost:8200 ./scripts/init-pki.sh test   # or sandbox / prod
```
Idempotent — safe to re-run; it skips `secrets enable` for engines already mounted (note: it will still regenerate/replace the root CA on that path each run).

Each engine gets a `leaf` role for issuing end-entity certs (EC P-256, `key_usage=DigitalSignature,ContentCommitment`, `ext_key_usage=ServerAuth,ClientAuth`, `max_ttl=19800h` i.e. 825 days — matching the reference services' cert profile). In **test** and **sandbox**, the role is locked to `allowed_domains=<mount>.<environment>.internal` (+ subdomains/bare domain), e.g. `pid-issuer.test.internal`, `wallet-provider.sandbox.internal`. **prod** has no domain convention defined yet, so its role still uses `allow_any_name=true` — tighten this once a real prod domain is chosen.

`pid-issuer` additionally gets an `encryption` role (same EC/TTL settings, but `key_usage=KeyEncipherment,DataEncipherment,KeyAgreement`) for its two extra key pairs — `nonce-encryption` and `request-encryption` — which the reference ecosystem bundles into the same keystore as the main service cert for OpenID4VCI request/nonce encryption. These have fixed, non-hostname common names, so they're restricted via `allowed_domains=nonce-encryption,request-encryption` + `allow_bare_domains=true` + `enforce_hostnames=false` — Vault/OpenBao PKI roles have no dedicated "exact common name" field, so this is the closest equivalent (note: `allowed_common_names` is *not* a real Vault/OpenBao PKI role parameter and is silently ignored if used — this was tried and confirmed broken during development).

KV init script (enables a `kv-v2` engine, default path `secret`, idempotent — nothing else in this repo mounts one, `bao kv put`/`get` fail without it):
```bash
BAO_TOKEN=<root_token> BAO_ADDR=http://localhost:8200 ./scripts/init-kv.sh test   # or sandbox / prod [kv-path]
```

There's no test suite, linter, or CI config in this repo. A Spring Boot REST client that calls these `issue`/`ca` endpoints lives in `pki-cert-client/` (see below).

## Architecture

- **One Dockerfile, three services.** `docker-compose.yml` defines `openbao-test`, `openbao-sandbox`, `openbao-prod` — same `build: .`, same `config/bao.hcl` bind-mounted into each — differentiated only by the `BAO_ENV` env var, the exposed host port (8200/8201/8202), and the compose `profiles:` used to select which one(s) to start. Docker Compose profiles are the mechanism for "pick an environment," not separate compose files.
- **`config/bao.hcl` is identical across environments.** The file storage backend, TCP listener (TLS disabled), and UI flag apply to all three. The line `environment = "${BAO_ENV:test}"` at the bottom of `bao.hcl` is not a real OpenBao config field — it produces an `unknown or unsupported field` warning at startup and is ignored. Actual per-environment behavior comes only from the `BAO_ENV` / `BAO_API_ADDR` / `BAO_UI` environment variables set in `docker-compose.yml`, not from anything in the HCL file.
- **Base image runs as a non-root user.** `openbao/openbao:2.6.2` sets `USER openbao` (uid 100). The Dockerfile must `USER root` before `apk add`/`chown` and switch back to `USER openbao` before `CMD` — installing packages or writing to `/openbao/*` as the default user fails with permission errors.
- **Base image is pinned, not `:latest`.** `openbao/openbao:latest` moved from v2.6.2 → v2.7.0 on 2026-09-23, and v2.7.0 removed the `file` storage backend this whole repo's `config/bao.hcl` relies on entirely (`unknown storage type file` on startup) — exactly as v2.6.2's own deprecation warning said it would ("by v2.7.0"). Discovered by rebuilding against Rancher Desktop's docker daemon and hitting a crash-looping pod. The real fix is migrating off `file` storage to Raft integrated storage (also gets rid of the single-replica/no-HA limitation below); pinning to `2.6.2` is the stopgap. Don't bump this tag without checking the storage backend still works.
- **OpenShift arbitrary-UID compatibility.** OpenShift's default `restricted` SCC ignores a Dockerfile's `USER` and instead runs the container as a random UID in group `0`. `/openbao/data` and `/openbao/logs` are `chown`ed to group `0` and made group-writable (`chmod g=u`) so any such UID can still read/write them — verified with `docker run --user 12345:0`. `pki-cert-client`'s image needs no equivalent fix (it writes nothing at runtime), but still declares a non-root `USER` for plain `docker run`.
- **dumb-init path.** Alpine's `dumb-init` package installs to `/usr/bin/dumb-init`, not `/sbin/dumb-init` — the `ENTRYPOINT` must match.
- **Known gap:** `docker-compose.yml` bind-mounts `./config/pki-setup.sh` into every container, but that file does not exist in the repo (only `config/bao.hcl` and `scripts/init-pki.sh` do). Docker silently creates it as an empty directory on the host when the bind-mount source is missing — this doesn't break container startup, but nothing at `/openbao/config/pki-setup.sh` actually runs. PKI bootstrap is not automatic on container start; `scripts/init-pki.sh` (and, if you need a KV store, `scripts/init-kv.sh`) must be run manually (from the host, with `bao` CLI installed, or via `docker compose exec` into the container) after unsealing.
- **Env files don't fully match environments.** `.env.test` and `.env.prod` exist; `.env.sandbox` (referenced by the README) does not. `docker-compose.yml` does not actually load any of these via `env_file:` — environment values are hardcoded per-service in the `environment:` blocks instead.
- **Volumes.** Each environment persists to its own named volume (`openbao_test_data`, `openbao_sandbox_data`, `openbao_prod_data`) so state doesn't cross environments.
- **`pki-cert-client/`** is a separate Maven/Spring Boot app (Java 21, `spring-boot-starter-web`), not infrastructure config. `{ca}` is `pid-issuer`, `verifier-backend`, `wallet-provider`, or `trust-source`. It returns real **PKCS12 keystores** (binary `application/x-pkcs12`), not raw PEM — matching what the actual ecosystem services load:
  - `POST /api/certificates/{ca}` — single-key keystore (issues via the `leaf` role)
  - `POST /api/certificates/pid-issuer/bundle` — three-key keystore matching the ecosystem's `pid_issuer.p12` (main cert + `nonce-encryption` + `request-encryption`, aliased exactly as in the reference script)
  - `GET /api/certificates/{ca}/ca` — the CA's root cert as PEM
  - `GET /api/certificates/{ca}/truststore` — PKCS12 truststore (alias `root_ca`) containing just that CA's root cert, for a peer service to trust
  - All keystore endpoints accept an optional `password` field/param in the request body (JSON: `commonName`, `ttl`, `password`); defaults to `changeit` if omitted.
  - PEM→keystore conversion (`Pkcs12KeystoreBuilder`) uses only JDK built-ins (`KeyStore`, `CertificateFactory`, `KeyFactory` with `PKCS8EncodedKeySpec`) — no Bouncy Castle needed, because certs are requested from OpenBao with `private_key_format=pkcs8`, which the JDK can parse directly for EC keys.
  - Configured via `OPENBAO_ADDR` and `OPENBAO_TOKEN` env vars (see `pki-cert-client/src/main/resources/application.yml`). Build with `mvn package -DskipTests`, run with `java -jar target/pki-cert-client-0.1.0.jar`. Default port 8080 is a common local conflict (e.g. with `k9s`) — override with `SERVER_PORT` if the app appears to start but every request 307-redirects to `https://` on the same port, which means something else already owns that port.
- **Known gap:** cross-service trust bundling (e.g. the reference ecosystem's `trusted_issuers.p12`, which holds a *specific peer's* cert, not just its own CA) isn't implemented — `GET /api/certificates/{ca}/truststore` only ever contains `{ca}`'s own root, not another service's leaf cert. Building that needs the caller to specify which peer(s) to trust; not designed yet.
- **`openshift/`** is a Kustomize base (`openshift/base/`) + three overlays (`openshift/overlays/{test,sandbox,prod}/`) mirroring the docker-compose environment split. Each overlay just sets the namespace and patches `BAO_ENV`. `pki-cert-client` reaches OpenBao via the in-namespace `openbao` Service DNS name (`http://openbao:8200`) — that only works because both Deployments land in the same namespace/overlay. OpenBao's readiness probe intentionally treats "sealed" as not-ready (`GET /v1/sys/health`); the liveness probe is a plain TCP check so a freshly-restarted, still-sealed pod isn't killed by Kubernetes while waiting for a manual `bao operator unseal` (there's no auto-unseal configured — same manual-unseal workflow as `GETTING_STARTED.md`). `pki-cert-client`'s two probes hit `spring-boot-starter-actuator`'s `/actuator/health/{liveness,readiness}` (auto-enabled because Boot detects the `KUBERNETES_SERVICE_HOST` env var Kubernetes injects into every pod). The `openbao-token` Secret is deliberately not applied by the kustomization (`base/pki-cert-client/secret.example.yaml` is a template, excluded from `resources:`) — create the real one out-of-band per namespace before applying, same spirit as this repo's gitignored `.test.env`/`.sandbox.env`/`.prod.env`.
- **`openshift/base/rotation/`** is a weekly `CronJob` (`cert-rotator`) that keeps the 4 issued keystores fresh without any changes to `pki-cert-client` itself — it just calls the same HTTP endpoints an external caller would. Two containers per run, sharing an `emptyDir`: an `initContainer` (`curlimages/curl`) calls `pki-cert-client`'s issue endpoints and writes each `.p12` to `/work`; the main container (`alpine/k8s` — **not** `bitnami/kubectl` or `rancher/kubectl`, both tried first: the former's tag doesn't exist, the latter has no shell to run the script with) reads `/work` and `kubectl apply`s each as a `<ca>-keystore` Secret (`pid-issuer-keystore` is the 3-key bundle). Always reissues and overwrites on every run rather than tracking what's actually due for renewal — requests 90-day (`2160h`) certs on a weekly schedule, so anything downstream stays far from expiry even if several runs are missed; simpler than adding real expiry-tracking state. `ENVIRONMENT` (used to build each cert's `commonName` as `<ca>.<environment>.internal`, matching the `allowed_domains` role restriction) is patched per overlay the same way `BAO_ENV` is on the `openbao` Deployment. The `cert-rotator` ServiceAccount only has namespace-scoped `secrets` RBAC (`get`/`create`/`update`/`patch`) — no access to OpenBao itself; it authenticates purely by calling `pki-cert-client`, which already holds the Vault token. **Known gap:** downstream services still need their own watch-and-reload on these Secrets (e.g. Reloader) to actually pick up a rotated cert — not implemented here, since those services live in other repos.
