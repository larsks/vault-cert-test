#!/bin/sh

rm -rf artifacts
kind delete cluster -n vault-test
docker rm -f vault.vault-test step-ca.vault-test
