# OpenBao Vault - Wallet Ecosystem PKI

Docker/OpenShift setup for running [OpenBao](https://openbao.org/) (a Vault
fork) as the certificate authority for the EUDI wallet microservices in
[diggsweden/wallet-ecosystem](https://github.com/diggsweden/wallet-ecosystem):
**pid-issuer**, **verifier-backend**, **wallet-provider**, **trust-source**.
That reference repo generates static, locally-signed dev certificates with
`openssl`; this repo's OpenBao instances are meant to become the real issuer
for those same services once deployed to an OpenShift/Kubernetes cluster.

Three isolated environments — **test**, **sandbox**, **production** — each
with their own OpenBao instance, PKI hierarchy, and data volume.

## What's here

| Path | What it is |
|---|---|
| `docker-compose.yml`, `Dockerfile`, `config/` | OpenBao itself, run locally in Docker |
| `scripts/init-pki.sh` | Bootstraps the 4 PKI engines + roles in a running OpenBao instance |
| `scripts/init-kv.sh` | Enables a KV v2 secrets engine (`bao kv put`/`get`) — not mounted by default |
| `pki-cert-client/` | Spring Boot REST app that issues certs from OpenBao as PKCS12 keystores |
| `openshift/` | Kustomize manifests (base + test/sandbox/prod overlays) to run both of the above on OpenShift, plus a `CronJob` that rotates issued certs weekly |
| `GETTING_STARTED.md` | Full step-by-step: build → start → init → unseal → generate PKI |
| `CLAUDE.md` | Detailed architecture notes, gotchas, and non-obvious decisions (written for AI-assisted development, but useful to anyone working in this repo) |

## Architecture

### PKI Engines

Each environment mounts four PKI secrets engines, one per wallet-ecosystem
service, using **EC P-256** keys to match that ecosystem's real certificate
profile:

- **`pid-issuer`** — PID Issuer CA. Also has an `encryption` role for two
  extra key pairs (`nonce-encryption`, `request-encryption`) used for
  OpenID4VCI request/nonce encryption — the reference ecosystem bundles all
  three into one keystore, and `pki-cert-client` does the same (see below).
- **`verifier-backend`** — Verifier Backend CA.
- **`wallet-provider`** — Wallet Provider CA.
- **`trust-source`** — Trust Source CA.

Every engine gets a `leaf` role for issuing end-entity certs (825-day max
TTL, matching the reference profile's cert lifetime). In **test** and
**sandbox**, issuance is locked to `<mount>.<environment>.internal` (+
subdomains), e.g. `pid-issuer.test.internal` — anything else is rejected.
**prod** has no real domain convention yet, so it's still wide open
(`allow_any_name=true`) until one is chosen.

Deliberately **not** replicated: the reference profile's eIDAS QC statement
certificate extensions (custom ASN.1 OIDs, `organizationIdentifier`) — Vault/
OpenBao's PKI `issue` API can't emit those; doing so would mean generating
CSRs ourselves and using `sign-verbatim` instead of `issue`.

### Environments

| Environment | Port | Compose profile |
|---|---|---|
| Test | 8200 | `test` |
| Sandbox | 8201 | `sandbox` |
| Production | 8202 | `prod` |

Each environment has isolated data storage (a separate named Docker volume),
its own PKI hierarchy, and its own root CAs — nothing is shared across
environments.

## Quick start

See **[GETTING_STARTED.md](GETTING_STARTED.md)** for the full walkthrough
(build, start, init, unseal, generate PKI, verify). Condensed version:

```bash
docker compose build
docker compose --profile test up -d openbao-test
docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-test bao operator init -key-shares=1 -key-threshold=1
# save the unseal key + root token from the output above
docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-test bao operator unseal <unseal_key>
BAO_TOKEN=<root_token> BAO_ADDR=http://localhost:8200 ./scripts/init-pki.sh test
```

Web UI: http://localhost:8200/ui (log in with the root token).

## Issuing certificates

`pki-cert-client` is a small Spring Boot app that calls OpenBao's `issue` API
and packages the result into a real **PKCS12 keystore** — the format the
actual wallet-ecosystem services load, not raw PEM.

```bash
cd pki-cert-client
mvn package -DskipTests
OPENBAO_ADDR=http://localhost:8200 OPENBAO_TOKEN=<root_token> java -jar target/pki-cert-client-0.1.0.jar
```

| Endpoint | Returns |
|---|---|
| `POST /api/certificates/{ca}` | Single-key keystore for `{ca}` (`pid-issuer`, `verifier-backend`, `wallet-provider`, or `trust-source`) |
| `POST /api/certificates/pid-issuer/bundle` | Three-key keystore matching the ecosystem's `pid_issuer.p12` — main cert + `nonce-encryption` + `request-encryption` |
| `GET /api/certificates/{ca}/ca` | That CA's root certificate, as PEM |
| `GET /api/certificates/{ca}/truststore` | PKCS12 truststore containing just that CA's root cert |

`POST` bodies take `{"commonName": "...", "ttl": "720h", "password": "..."}`
(`password` defaults to `changeit`). Default port 8080 — override with
`SERVER_PORT` if something else on your machine already holds it (e.g. `k9s`
does this by default and silently swallows requests without an obvious
error).

## Storing app secrets (KV)

The four PKI engines above don't help if you just want to stash a plain
secret. Nothing enables a KV engine by default — run this once per
environment first:

```bash
BAO_TOKEN=<root_token> BAO_ADDR=http://localhost:8200 ./scripts/init-kv.sh test   # or sandbox / prod
```

Then:

```bash
bao kv put secret/some-app foo=bar
bao kv get secret/some-app
```

Same commands work identically once OpenBao is deployed to the cluster — it's
the same API either way. Idempotent — safe to re-run per environment.

## Deploying to OpenShift

`openshift/` is a Kustomize base + three overlays mirroring the
test/sandbox/prod split above:

```bash
kubectl kustomize openshift/overlays/test   # sanity-check the rendered manifests

oc new-project openbao-test
oc create secret generic openbao-token --from-literal=token=<vault-token> -n openbao-test
oc apply -k openshift/overlays/test
```

Both Dockerfiles (`Dockerfile`, `pki-cert-client/Dockerfile`) run correctly
under OpenShift's default `restricted` SCC (arbitrary UID, group `0`).
Image references in `openshift/base/kustomization.yaml` are placeholders —
there's no CI/registry push pipeline in this repo yet, so images need to be
built and pushed manually before applying. See `CLAUDE.md` for the full
breakdown of what each manifest does and why.

### Automatic certificate rotation

A weekly `CronJob` (`openshift/base/rotation/`) keeps the 4 issued keystores
fresh — it just calls `pki-cert-client`'s own endpoints and writes the
results as `<ca>-keystore` Secrets (`pid-issuer-keystore` holds the 3-key
bundle), no changes to the app itself. Requests 90-day certs on a weekly
schedule, so it doesn't track what's actually due for renewal — it just
always reissues, which is simpler and leaves a wide safety margin even if
several runs are missed. Downstream services still need their own
watch-and-reload on these Secrets to pick up a rotation (e.g.
[Reloader](https://github.com/stakater/Reloader)) — not set up here, since
those services live in other repos.

## Secrets

Never commit real unseal keys, root tokens, or `.p12` passwords. This repo's
`.gitignore` already excludes `.test.env` / `.sandbox.env` / `.prod.env` —
save generated keys there (see `GETTING_STARTED.md` step 3) rather than
inline in shell history or scripts. On OpenShift, the `openbao-token` Secret
is deliberately excluded from the Kustomize base
(`openshift/base/pki-cert-client/secret.example.yaml` is a template only) —
create the real one per namespace with `oc create secret`, never commit it.

## Known limitations

- **prod** has no domain convention defined, so its PKI roles are still
  `allow_any_name=true` — tighten once a real prod hostname scheme exists.
- OpenBao runs single-replica on the `file` storage backend in every
  environment — no HA. A real deployment should move to Vault/OpenBao's Raft
  integrated storage (or an external backend).
- No auto-unseal — every restart requires a manual `bao operator unseal`.
- Cross-service trust bundling (e.g. a verifier trusting one specific PID
  issuer's cert, like the reference ecosystem's `trusted_issuers.p12`) isn't
  implemented — `GET /api/certificates/{ca}/truststore` only ever contains
  `{ca}`'s own root, not a peer's leaf cert.
- `docker-compose.yml` bind-mounts `./config/pki-setup.sh`, which doesn't
  exist in this repo (Docker silently creates it as an empty host directory).
  Harmless, but PKI bootstrap is not automatic — `scripts/init-pki.sh` must
  be run manually after unsealing.

## References

- [OpenBao Documentation](https://openbao.org/docs/)
- [PKI Secrets Engine](https://openbao.org/docs/secrets/pki/)
- [diggsweden/wallet-ecosystem](https://github.com/diggsweden/wallet-ecosystem) — the reference stack this PKI setup is aligned with

## License

[Add your license here]
