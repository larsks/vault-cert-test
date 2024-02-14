all: bank-vault.yaml

bank-vault.yaml: $(wildcard src/*)
	kustomize build --enable-helm src > $@ || { rm -f $@; exit 1; }

clean:
	rm -f bank-vault.yaml
