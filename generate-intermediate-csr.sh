#!/bin/bash

set -x

if [[ -f artifacts/pki_nerc_intermediate.crt.json ]]; then
	echo "Intermediate certificate already exists."
	exit
fi

vault write -format=json pki_nerc_intermediate/intermediate/generate/internal \
	max_path_length=0 \
	key_bits=4096 \
	common_name="NERC Internal Intermediate CA" > artifacts/pki_nerc_intermediate.csr.json

vault write -format=json pki_nerc_root/root/sign-intermediate max_path_length=0 \
	key_bits=4096 \
	common_name="NERC Internal Intermediate CA" csr=@<(jq -r .data.csr artifacts/pki_nerc_intermediate.csr.json) \
	format=pem_bundle ttl=43800h > artifacts/pki_nerc_intermediate.crt.json

vault write pki_nerc_intermediate/intermediate/set-signed \
	certificate=@<(jq -r .data.certificate artifacts/pki_nerc_intermediate.crt.json)
