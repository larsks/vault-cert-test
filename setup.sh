#!/bin/bash

VAULT_VERSION=1.10.3

container_addr() {
	docker container inspect "$1" | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress'
}

container_is_running() {
	docker container inspect "$1" > /dev/null 2>&1
}

apply_manifests() {
	echo "🗎 apply manifests from $1"
	until kubectl apply -k "$1"; do
		echo "Failed to apply $1; retrying..." >&2
		sleep 5
	done
}

wait_for_pods() {
	local ns=$1 condition=$2
	shift 2

	echo "🕒 waiting for pods in $ns"
	while ! kubectl -n "$ns" wait --for condition="$condition" pod "$@" 2> /dev/null; do
		sleep 1
	done
}

start_cluster() {
	echo "🟢 start kubernetes cluster"

	if ! kind get clusters | grep -q vault-test; then
		kind create cluster --config kind.yaml -n vault-test --kubeconfig artifacts/kubeconfig
	fi

	container_addr vault-test-control-plane > artifacts/cluster.address

	export KUBECONFIG=$PWD/artifacts/kubeconfig
	docker exec vault-test-control-plane cat /etc/kubernetes/pki/ca.crt > artifacts/ca.crt
}

start_vault() {
	echo "🟢 start vault"
	if ! container_is_running vault.vault-test; then
		docker run --rm -d --name vault.vault-test -p 8200:8200 \
			--network kind \
			--hostname vault.vault-test \
			hashicorp/vault:${VAULT_VERSION} > artifacts/vault.cid
	fi

	container_addr vault.vault-test > artifacts/vault.address

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
	echo "🟢 start step-ca"
	if ! container_is_running step-ca.vault-test; then
		docker run --rm -d --name step-ca.vault-test -p 9000:9000 \
			--network kind \
			--hostname step-va.vault-test \
			-e DOCKER_STEPCA_INIT_NAME=vault-test-ca \
			-e DOCKER_STEPCA_INIT_DNS_NAMES=localhost,step-ca.vault-test \
			-e DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT=true \
			-e DOCKER_STEPCA_INIT_ADMIN_SUBJECT=step \
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

apply_manifests manifests/external-secrets
apply_manifests manifests/nginx-ingress
apply_manifests manifests/cert-manager

wait_for_pods external-secrets Ready -l app.kubernetes.io/name=external-secrets-webhook
apply_manifests manifests/vault-integration

wait_for_pods cert-manager Ready -l app.kubernetes.io/name=webhook
apply_manifests manifests/step-issuer

kubectl -n external-secrets get secret eso-vault-auth-token -o json | jq -r .data.token | base64 -d > artifacts/eso-vault-auth-jwt

sh configure-vault.sh
sh configure-step-issuer.sh

apply_manifests manifests/certificates

wait_for_pods ingress-nginx Ready -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller
apply_manifests manifests/ingresses
