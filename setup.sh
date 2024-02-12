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

set -eu

mkdir -p artifacts

create_kind_cluster vault-cluster
create_kind_cluster client-cluster

KUBECONFIG=artifacts/kubeconfig-vault-cluster kubectl apply -k manifests/vault-cluster --server-side
KUBECONFIG=artifacts/kubeconfig-client-cluster kubectl apply -k manifests/client-cluster --server-side
