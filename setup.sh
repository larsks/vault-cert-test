#!/bin/bash

: "${HOSTFILE:=$HOME/.config/hosts}"

create_kind_cluster() {
	local cluster_name=$1

	if ! kind get clusters | grep -q "$cluster_name"; then
		if ! kind create cluster -n "$cluster_name" --config "clusters/$cluster_name.yaml" --kubeconfig "artifacts/kubeconfig-$cluster_name"; then
			cat <<-EOF >&2
			ERROR: Failed to create cluster $cluster_name.

			This can happen if either of fs.inotify.max_user_instances or fs.inotify.max_user_watches are too low. Consider setting:

			    fs.inotify.max_user_instances = 1000
			    fs.inotify.max_user_watches = 1000000

			If that doesn't help, consider just trying again -- the behavior of kind with multiple clusters seems a bit flaky,
			and I haven't figured out all the error conditions yet.
			EOF
		fi
	fi

	# extract node addresses into a hosts-format file
	docker container ps --filter label=io.x-k8s.kind.cluster="${cluster_name}" --format '{{.Names}}' |
		xargs -INODE docker container inspect "NODE" \
		--format '{{.NetworkSettings.Networks.kind.IPAddress}} NODE' \
		> "artifacts/${cluster_name}.hosts"
}

apply_manifests() {
	until kubectl apply -k "$1" --server-side; do
		echo "failed to apply manifests in $1; will retry..." >&2
		sleep 5
	done
}

with() {
	local cluster_name=$1
	KUBECONFIG=artifacts/kubeconfig-${cluster_name} . <(cat)
}

wait_for() {
	local namespace=$1
	local resource=$2
	until kubectl -n "$namespace" get "$resource" > /dev/null 2>&1; do
		sleep 1
	done
}

set -eu

mkdir -p artifacts

create_kind_cluster vault-cluster
create_kind_cluster client-cluster

with vault-cluster <<EOF
apply_manifests manifests/vault-cluster/stage1
EOF

with client-cluster <<EOF
apply_manifests manifests/client-cluster/stage1
EOF

with vault-cluster <<EOF
until kubectl -n vault-operator wait deployment/vault-operator --for condition=available; do
	sleep 1
done
EOF

# Warning, hacky! This only makes sense for a single-node "cluster".
vault_cluster_addr=$(awk '{print $1; exit}' artifacts/vault-cluster.hosts)

with vault-cluster <<EOF
tmpdir=\$(mktemp -d kustomizeXXXXXX)
cat > "\$tmpdir/kustomization.yaml" <<END_YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../manifests/lib/vault-instance

patches:
  - patch: |
      apiVersion: vault.banzaicloud.com/v1alpha1
      kind: Vault
      metadata:
        name: vault
      spec:
        ingress:
          spec:
            rules:
              - host: vault.${vault_cluster_addr}.nip.io
                http:
                  paths:
                    - path: /
                      pathType: Prefix
                      backend:
                        service:
                          name: vault
                          port:
                            name: api-port
END_YAML

apply_manifests "\$tmpdir"
rm -rf \$tmpdir

wait_for vault secret/vault-unseal-keys
while :; do
	kubectl -n vault get secret/vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d > artifacts/vault-root
	[[ -s artifacts/vault-root ]] && break
	sleep 1
done
EOF

with vault-cluster <<EOF
apply_manifests vault-config
apply_manifests cert-manager-config

until kubectl -n vault wait job/configure-vault --for condition=Complete; do
	sleep 1
done
EOF

# This file will load automatically if you are using direnv [1]. This allows
# you to use `kubectl` and `vault` without additional configuration.
#
# [1]: https://direnv.net/
cat > .envrc <<EOF
export KUBECONFIG=\$PWD/artifacts/kubeconfig-vault-cluster
export VAULT_ADDR=http://vault.${vault_cluster_addr}.nip.io
export VAULT_TOKEN=$(cat artifacts/vault-root)
EOF

. ./.envrc
bash generate-intermediate-csr.sh

