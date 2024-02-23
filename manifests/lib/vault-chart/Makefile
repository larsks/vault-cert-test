all: vault.yaml

vault.yaml: src/kustomization.yaml
	kustomize build --enable-helm src > $@ || { rm -f $@; exit 1; }

clean:
	rm -f vault.yaml
