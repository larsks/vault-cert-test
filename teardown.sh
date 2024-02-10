#!/bin/sh

rm -rf artifacts
kind delete cluster -n vault-test
docker rm -f vault
docker rm -f step-ca
