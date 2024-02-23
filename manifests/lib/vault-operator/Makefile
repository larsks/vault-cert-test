all: vault-operator.yaml

vault-operator.yaml: $(wildcard src/*)
	kustomize build --enable-helm src > $@ || { rm -f $@; exit 1; }

clean:
	rm -f vault-operator.yaml
