#!/bin/bash

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
}

apply_manifests() {
	until kubectl apply -k "$1" --server-side; do
		echo "failed to apply manifests in $1; will retry..." >&2
		sleep 5
	done
}

set -eu

mkdir -p artifacts

create_kind_cluster vault-cluster
create_kind_cluster client-cluster

KUBECONFIG=artifacts/kubeconfig-vault-cluster apply_manifests manifests/vault-cluster/stage1
KUBECONFIG=artifacts/kubeconfig-client-cluster apply_manifests manifests/client-cluster/stage1
