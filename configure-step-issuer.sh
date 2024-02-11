#!/bin/bash

if ! [ -f artifacts/step-issuer-password ]; then
	tr -dc 'A-Za-z0-9!?%=' < /dev/urandom | head -c 30 > artifacts/step-issuer-password
fi

if ! step ca provisioner list | jq -r '.[]|.name' | grep -q step-issuer; then
	echo "creating step-issuer provisioner"
	step ca provisioner add step-issuer --type JWK --create \
		--admin-provisioner admin \
		--admin-subject step --admin-password-file artifacts/step-ca-password \
		--password-file artifacts/step-issuer-password
fi

step ca provisioner list | jq -r '.[]|select(.name == "step-issuer")|.key.kid' > artifacts/step-issuer-kid


cat <<EOF > artifacts/step-issuer.yaml
apiVersion: v1
metadata:
  name: step-certificates-provisioner-password
type: generic
stringData:
  password: $(cat artifacts/step-issuer-password)
kind: Secret
---
apiVersion: certmanager.step.sm/v1beta1
kind: StepIssuer
metadata:
  name: step-issuer
spec:
  url: https://step-ca.vault-test:9000
  caBundle: $(base64 -w 0 artifacts/step-ca-root-cert.crt)
  provisioner:
    name: step-issuer
    kid: $(cat artifacts/step-issuer-kid)
    passwordRef:
      name: step-certificates-provisioner-password
      key: password
EOF

kubectl apply -n default -f artifacts/step-issuer.yaml --server-side
