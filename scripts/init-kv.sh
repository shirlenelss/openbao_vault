#!/bin/bash

# KV Secrets Engine Initialization Script
# Enables a KV v2 secrets engine at "secret/" so `bao kv put`/`bao kv get`
# work. Nothing else in this repo enables one - scripts/init-pki.sh only
# mounts the PKI engines.

set -e

ENVIRONMENT=${1:-test}
BAO_ADDR=${BAO_ADDR:-http://localhost:8200}
BAO_TOKEN=${BAO_TOKEN}

case $ENVIRONMENT in
    test)
        BAO_ADDR="http://localhost:8200"
        ;;
    sandbox)
        BAO_ADDR="http://localhost:8201"
        ;;
    prod)
        BAO_ADDR="http://localhost:8202"
        ;;
esac

if [ -z "$BAO_TOKEN" ]; then
    echo "Error: BAO_TOKEN must be set to a token with permission to mount secrets engines" >&2
    exit 1
fi

export BAO_ADDR BAO_TOKEN

echo "Initializing KV secrets engine for $ENVIRONMENT environment at $BAO_ADDR"

kv_path=${2:-secret}

if bao secrets list -format=json | jq -e "has(\"${kv_path}/\")" > /dev/null 2>&1; then
    echo "KV engine already enabled at: $kv_path"
else
    echo "Enabling KV v2 engine at: $kv_path"
    bao secrets enable -path="$kv_path" -version=2 kv
fi

echo ""
echo "KV initialization complete for $ENVIRONMENT! Try:"
echo "  bao kv put ${kv_path}/some-app foo=bar"
echo "  bao kv get ${kv_path}/some-app"
