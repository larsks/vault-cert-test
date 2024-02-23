#!/bin/sh

rm -rf artifacts
kind delete cluster -n vault-cluster
kind delete cluster -n client-cluster
