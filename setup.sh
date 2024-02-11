#!/bin/bash

VAULT_VERSION=1.10.3

container_addr() {
	docker container inspect "$1" | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress'
}

container_is_running() {
	docker container inspect "$1" > /dev/null 2>&1
}

start_cluster() {
	echo "start kubernetes cluster"

	if ! kind get clusters | grep -q vault-test; then
		kind create cluster --config kind.yaml -n vault-test --kubeconfig artifacts/kubeconfig
	fi

	export KUBECONFIG=$PWD/artifacts/kubeconfig
	docker exec vault-test-control-plane cat /etc/kubernetes/pki/ca.crt > artifacts/ca.crt
}

start_vault() {
	echo "start vault"
	if ! container_is_running vault.vault-test; then
		docker run --rm -d --name vault.vault-test -p 8200:8200 \
			--network kind \
			--hostname vault.vault-test \
			hashicorp/vault:${VAULT_VERSION} > artifacts/vault.cid
	fi

	until docker logs vault.vault-test 2> /dev/null | grep -q 'Unseal Key'; do
		(( SECONDS % 5 == 0 )) && echo "waiting for vault unseal key"
		sleep 1
	done
	docker logs vault.vault-test 2> /dev/null | grep -A1 'Unseal Key' > artifacts/vault-creds.txt
	awk -F": " '/Unseal Key/ {print $2}' artifacts/vault-creds.txt > artifacts/vault-unseal-key
	awk -F": " '/Root Token/ {print $2}' artifacts/vault-creds.txt > artifacts/vault-root-token

	cat > artifacts/vault.env <<-EOF
	export VAULT_ADDR=http://127.0.0.1:8200
	export VAULT_TOKEN="$(cat artifacts/vault-root-token)"
	EOF
}

start_step_ca() {
	echo "start step-ca"
	if ! container_is_running step-ca.vault-test; then
		docker run --rm -d --name step-ca.vault-test -p 9000:9000 \
			--network kind \
			--hostname step-va.vault-test \
			-e DOCKER_STEPCA_INIT_NAME=vault-test-ca \
			-e DOCKER_STEPCA_INIT_DNS_NAMES=localhost,step-ca.vault-test \
			docker.io/smallstep/step-ca:0.25.2 > artifacts/step-ca.cid
	fi

	until docker logs step-ca.vault-test 2> /dev/null | grep -q 'administrative password'; do
		(( SECONDS % 5 == 0 )) && echo "waiting for step-ca administrative password"
		sleep 1
	done
	docker logs step-ca.vault-test 2> /dev/null | awk -F": " '/administrative password/ {print $2}' > artifacts/step-ca-password
	curl -sSf -k https://localhost:9000/roots.pem > artifacts/step-ca-root-cert.crt
	step certificate fingerprint artifacts/step-ca-root-cert.crt > artifacts/step-ca-root-fingerprint
	step ca bootstrap --context vault-test -f --ca-url https://localhost:9000 --fingerprint "$(cat artifacts/step-ca-root-fingerprint)"
}

set -eu

mkdir -p artifacts

start_step_ca
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

kubectl -n external-secrets get secret eso-vault-auth-token -o json | jq -r .data.token | base64 -d > artifacts/jwt-token

sh configure-vault.sh
