#!/bin/bash

# PKI Initialization Script
# Initializes Root CAs for the OpenID4VCI wallet ecosystem services, aligned
# with diggsweden/wallet-ecosystem: pid-issuer, verifier-backend,
# wallet-provider, trust-source. Uses EC P-256 keys to match those services'
# real certificate profile (minus eIDAS QC statement extensions, which Vault's
# PKI issue API cannot produce and would require CSR + sign-verbatim instead).

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
    echo "Error: BAO_TOKEN must be set to a token with permission to mount and configure PKI engines" >&2
    exit 1
fi

export BAO_ADDR BAO_TOKEN

echo "Initializing PKI for $ENVIRONMENT environment at $BAO_ADDR"

# Function to enable a PKI secrets engine (idempotent) and allow long-lived root CAs
enable_pki_engine() {
    local pki_path=$1

    if bao secrets list -format=json | jq -e "has(\"${pki_path}/\")" > /dev/null 2>&1; then
        echo "PKI engine already enabled at: $pki_path"
    else
        echo "Enabling PKI engine at: $pki_path"
        bao secrets enable -path="$pki_path" pki
    fi

    # Default max_lease_ttl (768h) is too short for a 10-year root CA
    bao secrets tune -max-lease-ttl=87600h "$pki_path" > /dev/null
}

# Function to generate an EC (P-256) root CA, matching the ecosystem's key type
generate_root_ca() {
    local pki_path=$1
    local ca_name=$2
    local common_name=$3

    echo "Generating root CA for: $ca_name"

    bao write -field=certificate "$pki_path/root/generate/internal" \
        common_name="$common_name" \
        key_type=ec \
        key_bits=256 \
        ttl=87600h > "/tmp/${pki_path}_root_ca.crt"

    echo "Root CA generated for $ca_name"
}

# Function to configure CA and CRL URLs
configure_pki_urls() {
    local pki_path=$1

    echo "Configuring URLs for: $pki_path"

    bao write "$pki_path/config/urls" \
        issuing_certificates="$BAO_ADDR/v1/$pki_path/ca" \
        crl_distribution_points="$BAO_ADDR/v1/$pki_path/crl"
}

# Function to create the role service leaf certificates are issued against.
# EC P-256, digitalSignature+nonRepudiation / serverAuth+clientAuth to match
# the ecosystem's service.cnf profile (QC statement extensions intentionally
# skipped - Vault's issue API has no way to emit those).
# test/sandbox are locked to <short_name>.<environment>.internal (+ subdomains);
# prod has no domain convention defined yet, so it stays permissive until one is set.
create_leaf_role() {
    local pki_path=$1
    local role_name=$2
    local short_name=$3

    echo "Creating role '$role_name' for: $pki_path"

    case "$ENVIRONMENT" in
        test|sandbox)
            local domain="${short_name}.${ENVIRONMENT}.internal"
            bao write "$pki_path/roles/$role_name" \
                key_type=ec \
                key_bits=256 \
                key_usage="DigitalSignature,ContentCommitment" \
                ext_key_usage="ServerAuth,ClientAuth" \
                allowed_domains="$domain" \
                allow_subdomains=true \
                allow_bare_domains=true \
                max_ttl=19800h > /dev/null
            ;;
        *)
            bao write "$pki_path/roles/$role_name" \
                key_type=ec \
                key_bits=256 \
                key_usage="DigitalSignature,ContentCommitment" \
                ext_key_usage="ServerAuth,ClientAuth" \
                allow_any_name=true \
                max_ttl=19800h > /dev/null
            ;;
    esac
}

# Function to create the pid-issuer's extra role for its nonce/request
# encryption keys (bundled alongside the main leaf cert into one keystore,
# same as the ecosystem's pid_issuer.p12). These use fixed, non-hostname
# common names. Vault/OpenBao PKI roles have no "exact common name" field -
# allowed_domains + allow_bare_domains is the closest match, with
# enforce_hostnames=false since these names aren't real hostnames (no dot).
create_encryption_role() {
    local pki_path=$1
    local role_name=$2

    echo "Creating role '$role_name' for: $pki_path"

    bao write "$pki_path/roles/$role_name" \
        key_type=ec \
        key_bits=256 \
        key_usage="KeyEncipherment,DataEncipherment,KeyAgreement" \
        ext_key_usage="ServerAuth,ClientAuth" \
        allowed_domains="nonce-encryption,request-encryption" \
        allow_bare_domains=true \
        allow_subdomains=false \
        enforce_hostnames=false \
        max_ttl=19800h > /dev/null
}

# Initialize PKI engines
echo ""
echo "=== PID Issuer CA ==="
enable_pki_engine "pid-issuer"
generate_root_ca "pid-issuer" "PID Issuer CA" "PID Issuer Root CA"
configure_pki_urls "pid-issuer"
create_leaf_role "pid-issuer" "leaf" "pid-issuer"
create_encryption_role "pid-issuer" "encryption"

echo ""
echo "=== Verifier Backend CA ==="
enable_pki_engine "verifier-backend"
generate_root_ca "verifier-backend" "Verifier Backend CA" "Verifier Backend Root CA"
configure_pki_urls "verifier-backend"
create_leaf_role "verifier-backend" "leaf" "verifier-backend"

echo ""
echo "=== Wallet Provider CA ==="
enable_pki_engine "wallet-provider"
generate_root_ca "wallet-provider" "Wallet Provider CA" "Wallet Provider Root CA"
configure_pki_urls "wallet-provider"
create_leaf_role "wallet-provider" "leaf" "wallet-provider"

echo ""
echo "=== Trust Source CA ==="
enable_pki_engine "trust-source"
generate_root_ca "trust-source" "Trust Source CA" "Trust Source Root CA"
configure_pki_urls "trust-source"
create_leaf_role "trust-source" "leaf" "trust-source"

echo ""
echo "PKI initialization complete for $ENVIRONMENT!"
