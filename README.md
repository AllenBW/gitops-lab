# gitops-lab

A small, real CI → GitOps pipeline on a home cluster, for learning Kubernetes,
Helm, Argo CD, and (later) progressive delivery and Terraform hands-on.

```
 PR ──► ci.yaml (go test, helm lint, kubeconform)          ◄── the gates
  │
merge to main
  │
  ▼
build.yaml: build image ─► push ghcr.io/<you>/hello:<sha> ─► open PR bumping envs/dev
                                                              │
                                                          merge it
                                                              │
                                                              ▼
              Argo CD (in your cluster) pulls the repo ─► syncs hello-dev automatically
                                                     └─► hello-prod waits for a manual Sync
```

The key idea: **CI never talks to the cluster.** CI produces an artifact and a
pull request. Git is the desired state; Argo CD pulls it and reconciles.
A deploy is a reviewable PR, and a rollback is `git revert`.

## Prerequisites

On macOS, run `make setup` (Homebrew required). It installs everything in the `Brewfile`,
starts Docker via colima (headless, no Docker Desktop needed) as a login service so it
survives reboots, and enables the repo git hooks.
It is safe to re-run. You also need a public GitHub repo (public keeps Argo CD and image pulls
credential-free; private is a later exercise).

## Layout

| Path | What it is |
|---|---|
| `app/` | Tiny Go service: `/` returns version, color, pod name; `/healthz` for probes |
| `charts/hello/` | Hand-written Helm chart (read every template, they're short) |
| `envs/dev`, `envs/prod` | Per-environment values. The image tag lives here, not in the chart |
| `argocd/root.yaml` | App of apps. The only thing you `kubectl apply` by hand |
| `argocd/apps/` | AppProject (tenant boundary) and one Application per environment |
| `.github/workflows/` | `ci.yaml` gates PRs; `build.yaml` builds and opens the deploy PR |
| `private/` | Gitignored; a separate private repo for your lab journal (`private/NOTES.md`). Not part of this repo |

## Phase 1: Kubernetes and Helm, no Argo yet

1. `make up`, then poke around: `kubectl get nodes`, `kubectl get pods -A -o wide`.
   Which `kube-system` pods run only on the control-plane node, and why?
2. `helm lint charts/hello` and `helm template hello charts/hello -f envs/dev/values.yaml`.
   Read the rendered YAML next to the templates until the mapping is obvious.
3. Build locally and load into kind, skipping the registry:
   `docker build -t hello:local app && kind load docker-image hello:local --name gitops-lab`
4. `helm install hello charts/hello -n scratch --create-namespace --set image.repository=hello --set image.tag=local`
5. Explore: `kubectl -n scratch get deploy,rs,pods,svc`, `kubectl describe pod`, `kubectl logs`.
   Delete a pod and watch the ReplicaSet replace it. Then `kubectl -n scratch scale deploy/hello --replicas=3`
   and curl it from a pod inside the cluster to see the pod name change:
   ```
   kubectl -n scratch run curl --rm -i --restart=Never --image=curlimages/curl:8.22.0 -- \
     sh -c 'for i in 1 2 3 4 5 6; do curl -s hello; echo; done'
   ```
   (Don't use `kubectl port-forward` for this: it tunnels to one pod, so the name never changes.)
6. Change the color: `helm upgrade hello charts/hello -n scratch --reuse-values --set color=green`.
   - `--reuse-values` matters. Without it, Helm resets every value you don't pass again, so your
     `--set image.*` from step 4 would vanish and the pod would try to pull `ghcr.io/...:latest`.
   - It will fail with `conflict with "kubectl" with subresource "scale" ... .spec.replicas`. That's
     on purpose: Helm 4 applies server-side, and the API server remembers that *you* set `replicas`
     with kubectl in step 5. Two owners, one field. Read the error, then decide: re-run with
     `--force-conflicts` to let Helm take the field back (watch replicas drop to the chart's 1).
     Argo CD's drift detection is the same idea.
   Then `helm history hello -n scratch` and `helm rollback hello 1 -n scratch`.
7. `helm uninstall hello -n scratch`. Phase 2 hands control to Argo.

## Phase 2: GitOps with Argo CD

1. Push this repo to GitHub. In repo settings, under **Actions → General**, allow
   GitHub Actions to create pull requests.
2. `make init REPO_URL=https://github.com/<you>/gitops-lab.git GHCR_OWNER=<you>`, commit, push.
   (Safe to re-run; it says so when there is nothing left to fill.)
3. The **build** workflow runs on any push to `main` that touches `app/`, so that push already
   started it (or run it from Actions → build → Run workflow). It builds amd64 and arm64 images,
   since kind on an Apple Silicon Mac runs arm64 nodes.
   After it pushes the first image, open the package on GitHub (your profile → Packages → hello)
   and set its visibility to **public**. Merge the newest deploy PR it opened; close older ones.
4. `make argocd`, `make password`, `make ui` → https://localhost:8443 (user `admin`).
5. `make bootstrap`. Watch root create the project, then hello-dev and hello-prod.
   Dev syncs on its own. Prod shows OutOfSync until you press Sync. That's the promotion gate.
   Don't Sync prod yet: its tag is still a placeholder (`latest` is never pushed), so it would
   go to ImagePullBackOff. Prod gets a real tag in the Promotion drill.
6. `make curl-dev`.

## Phase 3: Break it on purpose

Each drill teaches one behavior. Write what you saw in your journal.
Make every change through a PR. A `kubectl edit` to an Application gets reverted within seconds,
because root (app of apps) self-heals the Applications too.

- **Drift:** `kubectl -n hello-dev scale deploy/hello --replicas=5`. Self-heal puts it back. Why is that the point?
- **Bad deploy:** edit `envs/dev/values.yaml` to a tag that doesn't exist, PR, merge.
  Watch ImagePullBackOff. Argo shows the app Progressing for about 10 minutes, then Degraded:
  that's the Deployment's `progressDeadlineSeconds` (default 600) running out. Roll back with `git revert`, not kubectl.
- **Bad chart:** break a template's indentation in a PR. `ci.yaml` goes red, but notice that GitHub
  still lets you merge: a check only blocks once a ruleset requires it. That's Phase 5.
- **Tenant boundary:** in a PR, point an Application's `destination.namespace` at `kube-system`.
  The AppProject refuses it: `namespace 'kube-system' do not match any of the allowed destinations in project 'lab'`.
- **Promotion:** copy the tested tag from dev into `envs/prod/values.yaml` in a PR, merge, then Sync prod manually.
- **The bot-PR gotcha:** open the deploy PR the build workflow opened and look at its checks: there are none.
  The `ci` and `guard` runs it triggered sit in the Actions tab as `action_required` instead of running,
  because the PR was created with the default `GITHUB_TOKEN`. Fixing it (a GitHub App token) is a real
  agent-ready-delivery problem: automated PRs must go through the same checks as human ones.

## Phase 3.5 (optional): Run your own CI runners with ARC (outline)

Install Actions Runner Controller on the kind cluster with its two Helm charts
(`gha-runner-scale-set-controller`, then `gha-runner-scale-set`, both from
`oci://ghcr.io/actions/actions-runner-controller-charts/`), authenticated with a GitHub App.
Point one job's `runs-on:` at your scale set name and watch runner pods appear and disappear.
Bonus: manage the ARC install itself as an Argo CD Application.

**Security first:** GitHub warns against self-hosted runners on public repos, since a fork's PR can run
arbitrary code on your machine. Either make the repo private or use your runners only for jobs triggered
by `push` and `workflow_dispatch`, never `pull_request`.

What to notice: ARC's runners still wait on GitHub to queue jobs. Self-hosting changes *where* jobs run,
not *whether* GitHub is in the loop. Compare with ephemeral-VM approaches (e.g., RunsOn) in NOTES.md.

## Phase 4: Progressive delivery (outline)

Install Argo Rollouts, convert the Deployment to a `Rollout` with a canary strategy
(e.g. 25% → pause → 50% → pause → 100%), and change `color` to watch traffic shift.
Then add an AnalysisTemplate that fails the rollout automatically. You'll have to add
the `Rollout` kind to the AppProject's whitelist first. Notice how the tenant boundary pushes back.

## Phase 5: Terraform (outline)

Use the GitHub Terraform provider to manage this repo's settings and a ruleset requiring
the `ci` checks on `main`. Practice `plan`, `apply`, then change a setting in the GitHub UI
and run `plan` again to see drift. Commit `.terraform.lock.hcl`, never commit state.
