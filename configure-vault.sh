#!/bin/sh

set -eu

if ! vault auth tune kubernetes > /dev/null 2>&1; then
	vault auth enable kubernetes
fi

vault write auth/kubernetes/config \
    token_reviewer_jwt=@artifacts/jwt-token \
    kubernetes_host=https://vault-test-control-plane:6443 \
    kubernetes_ca_cert=@artifacts/ca.crt

vault policy write secret-reader vault/policies/secret-reader.hcl

vault write auth/kubernetes/role/secret-reader \
    bound_service_account_names=vault-secret-reader \
    bound_service_account_namespaces=external-secrets \
    policies=default,secret-reader \
    ttl=1h
