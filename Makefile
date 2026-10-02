# Usage: make help
# Pinned on purpose: `stable` moves under you, so two installs a week apart can differ.
# Upgrading Argo CD is a reviewed one-line PR. Override for a one-off: make argocd ARGOCD_VERSION=v3.x.y
ARGOCD_VERSION ?= v3.5.3
CLUSTER        ?= gitops-lab

.PHONY: help setup init up down argocd password ui bootstrap status curl-dev

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-12s %s\n", $$1, $$2}'

setup: ## Install tools (Brewfile), start Docker (colima), enable git hooks. Safe to re-run
	./scripts/setup.sh

init: ## Fill in placeholders: make init REPO_URL=https://github.com/you/gitops-lab.git GHCR_OWNER=you
	@test -n "$(REPO_URL)" && test -n "$(GHCR_OWNER)" || (echo "need REPO_URL and GHCR_OWNER"; exit 1)
	@files=$$(grep -rl '__REPO_URL__\|__GHCR_OWNER__' argocd charts envs); \
	if [ -z "$$files" ]; then echo "No placeholders left; nothing to do."; exit 0; fi; \
	perl -pi -e 's#__REPO_URL__#$(REPO_URL)#g; s#__GHCR_OWNER__#$(shell echo $(GHCR_OWNER) | tr A-Z a-z)#g' $$files; \
	echo "Placeholders filled. Commit and push."

up: ## Create the kind cluster
	@docker info >/dev/null 2>&1 || { echo "Docker is not running. Run: make setup"; exit 1; }
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

curl-dev: ## Curl the dev service 6 times from a pod inside the cluster
	@# Not a port-forward: that tunnels to a single pod, so you would never see load balancing.
	@# sleep 2: kubectl attaches after the container starts; without it the first replies are lost.
	@kubectl -n hello-dev run curl-$$$$ --rm -i --quiet --restart=Never --image=curlimages/curl:8.22.0 -- \
	  sh -c 'sleep 2; for i in 1 2 3 4 5 6; do curl -s hello; done'
