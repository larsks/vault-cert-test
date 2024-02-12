all: nginx-ingress.yaml

nginx-ingress.yaml:
	curl -o $@ -sSf https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
