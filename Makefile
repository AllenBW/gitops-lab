# Usage: make help
# Pin ARGOCD_VERSION to a real release tag (e.g. v3.x.y). Pinning is the lesson.
ARGOCD_VERSION ?= stable
CLUSTER        ?= gitops-lab

.PHONY: help init up down argocd password ui bootstrap status curl-dev

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-12s %s\n", $$1, $$2}'

init: ## Fill in placeholders: make init REPO_URL=https://github.com/you/gitops-lab.git GHCR_OWNER=you
	@test -n "$(REPO_URL)" && test -n "$(GHCR_OWNER)" || (echo "need REPO_URL and GHCR_OWNER"; exit 1)
	@grep -rl '__REPO_URL__\|__GHCR_OWNER__' argocd charts envs | xargs perl -pi -e 's#__REPO_URL__#$(REPO_URL)#g; s#__GHCR_OWNER__#$(shell echo $(GHCR_OWNER) | tr A-Z a-z)#g'
	@echo "Placeholders filled. Commit and push."

up: ## Create the kind cluster
	kind create cluster --config kind/cluster.yaml

down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

argocd: ## Install Argo CD into the cluster
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd --server-side --force-conflicts \
	  -f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml
	kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

password: ## Print the initial admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

ui: ## Port-forward the Argo CD UI to https://localhost:8443 (user: admin)
	kubectl -n argocd port-forward svc/argocd-server 8443:443

bootstrap: ## Apply the root app-of-apps. The last thing you apply by hand.
	kubectl apply -f argocd/root.yaml

status: ## Show Argo CD applications and the hello pods
	kubectl -n argocd get applications
	kubectl get pods -A -l app.kubernetes.io/name=hello -o wide

curl-dev: ## Hit the dev service through a port-forward
	@kubectl -n hello-dev port-forward svc/hello 8081:80 >/dev/null 2>&1 & \
	  sleep 2; curl -s localhost:8081; echo; kill $$!
