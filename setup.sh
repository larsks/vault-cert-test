#!/bin/sh

VAULT_VERSION=1.10.3

container_addr() {
	docker container inspect $1 | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress'
}

start_cluster() {
	if ! kind get clusters | grep -q vault-test; then
		kind create cluster --config kind.yaml -n vault-test --kubeconfig artifacts/kubeconfig
	fi

	export KUBECONFIG=$PWD/artifacts/kubeconfig
	kubectl -n external-secrets get secret eso-vault-auth-token -o json | jq -r .data.token | base64 -d > artifacts/jwt-token
	docker exec vault-test-control-plane cat /etc/kubernetes/pki/ca.crt > artifacts/ca.crt
}

start_vault() {
	if ! docker container inspect vault > /dev/null 2>&1; then
		docker run --rm -d --name vault -p 8200:8200 \
			--network kind \
			--hostname vault.vault-test \
			hashicorp/vault:${VAULT_VERSION}
	fi

	until docker logs vault 2> /dev/null | grep -q 'Unseal Key'; do
		sleep 1
	done
	docker logs vault 2> /dev/null | grep -A1 'Unseal Key' > artifacts/vault-creds.txt
	awk -F": " '/Unseal Key/ {print $2}' artifacts/vault-creds.txt > artifacts/vault-unseal-key
	awk -F": " '/Root Token/ {print $2}' artifacts/vault-creds.txt > artifacts/vault-root-token

	cat > artifacts/vault.env <<-EOF
	export VAULT_ADDR=http://127.0.0.1:8200
	export VAULT_TOKEN=$(cat artifacts/vault-root-token)
	EOF
}

set -eu

mkdir -p artifacts

start_cluster
start_vault

. artifacts/vault.env

until kubectl apply -k manifests/external-secrets; do
	echo "Failed to apply external secrets operator; retrying..." >&2
	sleep 5
done

until kubectl apply -k manifests/vault-integration; do
	echo "Failed to apply external secrets operator; retrying..." >&2
	sleep 5
done

sh configure-vault.sh
