#!/bin/sh

rm -rf artifacts
docker rm -f vault
kind delete cluster -n vault-test
