#!/bin/bash

# PKI Initialization Script
# Initializes Root and Intermediate CAs for each PKI engine

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

echo "Initializing PKI for $ENVIRONMENT environment at $BAO_ADDR"

# Function to generate root CA
generate_root_ca() {
    local pki_path=$1
    local ca_name=$2
    local common_name=$3
    
    echo "Generating root CA for: $ca_name"
    
    bao write -field=certificate "$pki_path/root/generate/internal" \
        common_name="$common_name" \
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

# Initialize PKI engines
echo ""
echo "=== PID Provider CA ==="
generate_root_ca "pki_pid" "PID Provider CA" "PID Provider Root CA"
configure_pki_urls "pki_pid"

echo ""
echo "=== Wallet Provider CA ==="
generate_root_ca "pki_walletprov" "Wallet Provider CA" "Wallet Provider Root CA"
configure_pki_urls "pki_walletprov"

echo ""
echo "=== Access CA ==="
generate_root_ca "pki_access" "Access CA" "Access Root CA"
configure_pki_urls "pki_access"

echo ""
echo "=== Registration CA ==="
generate_root_ca "pki_registration" "Registration CA" "Registration Root CA"
configure_pki_urls "pki_registration"

echo ""
echo "PKI initialization complete for $ENVIRONMENT!"
