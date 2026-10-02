# gitops-lab: notes for Claude

This is a **learning lab**, not a product. The goal is hands-on understanding of Kubernetes, Helm,
Argo CD, progressive delivery, and Terraform that the learner can explain out loud, not a finished repo.

## How to help
- Teach, don't just do. Explain what a command or manifest does and why before changing it. Let the
  learner type the important parts (templates, Rollout specs, Terraform); offer hints before full answers.
- After each phase or drill, prompt for a journal entry in `private/NOTES.md`.
- Ask before anything destructive (`make down`, deleting namespaces, force-pushing).
- Prefer GitOps fixes (a PR, `git revert`) over `kubectl` edits, except in drills that are about drift.

## Public / private split
This repo is public. `private/` is gitignored and is its own separate private repo (journal and personal
context). Never move, copy, or quote anything from `private/` into tracked files, commit messages, or PRs.
The `guard` workflow and `.githooks/pre-commit` fail if anything under `private/` is tracked.
Commit journal entries from inside `private/`; commit lab work from the root.

## Layout
See README.md. Phases 1–3 are built; Phase 3.5 (ARC self-hosted runners, optional), 4 (Argo Rollouts) and
5 (Terraform GitHub provider) are outlines for the learner to build. For 3.5, enforce the public-repo safety
rule in the README.

## Commands
`make help` lists everything. Go tests: `cd app && go test ./...`.
Chart checks: `helm lint charts/hello` and `helm template hello charts/hello -f envs/dev/values.yaml`.

@private/CLAUDE.md
