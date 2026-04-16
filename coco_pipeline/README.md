# CoCo Pipeline

This directory contains a Tekton pipeline that builds and runs **cococtl** (Confidential Containers operator CLI) to initialize CoCo and apply an application manifest with sidecar attestation.

## Pipeline Overview

The `coco-pipeline` performs the following steps:

1. **pull-cococtl** – Installs git, make, go; clones the cococtl repo from GitHub (`confidential-devhub/cococtl`, branch `main`) and runs `make build`.
2. **pull-repo** – Clones your application repository (requires authentication; uses the same Git credentials secret as the GitOps update task).
3. **auth-cluster** – Installs the OpenShift CLI (`oc`) and authenticates to the cluster using the pipeline service account.
4. **run-cococtl** – Runs cococtl init and apply with sidecar, kata-remote runtime, and Trustee:
   - `kubectl-coco init --enable-sidecar -o coco-config.toml --runtime-class kata-remote --cert-dir=./certs --no-upload --trustee-namespace=trustee-operator-system`
   - `kubectl-coco apply -f <source-manifest> --skip-apply --sidecar --no-initdata --convert-secrets --config coco-config.toml --cert-dir=./certs`

The first three tasks run in parallel; **run-cococtl** runs after all of them complete.

## Files

- `pipeline-coco.yaml` – Pipeline definition
- `pipelinerun-coco.yaml` – Example PipelineRun
- `clusterrolebinding-pipeline-nodes.yaml` – RBAC so pipeline SA can list nodes (required by cococtl)
- `tasks/` – Tekton tasks:
  - `task-pull-cococtl.yaml` – Clone and build cococtl
  - `task-pull-repo.yaml` – Clone app repo (authenticated, same secret as update-gitops)
  - `task-auth-cluster.yaml` – Install oc and create kubeconfig from in-cluster credentials
  - `task-run-cococtl.yaml` – Run cococtl init and apply

## Git credentials

The pipeline uses the same **`gitops-git-credentials`** secret as the build pipeline’s GitOps update. Edit placeholders in [`build_pipeline/secrets/secret-gitops-git-credentials.yaml`](../build_pipeline/secrets/secret-gitops-git-credentials.yaml) (`stringData`, **TODO**), apply it to `janine-dev`, then bind it to the `PipelineRun` workspace as in `pipelinerun-coco.yaml`.

## Usage

### Deploy Tasks First

```bash
# From repo root
oc apply -f coco_pipeline/tasks/

# Verify
oc get tasks -n janine-dev | grep -E 'pull-cococtl|pull-repo|auth-cluster|run-cococtl'
```

### Grant pipeline SA permission to list nodes (required for run-cococtl)

cococtl auto-detects node IPs via `kubectl get nodes`. The pipeline service account needs cluster-scoped permission to list nodes:

```bash
oc apply -f coco_pipeline/clusterrolebinding-pipeline-nodes.yaml
```

### Git Credentials for pull-repo

The **pull-repo** task uses the same secret as the build pipeline’s GitOps update: `gitops-git-credentials`. If you already use that for `task-update-gitops`, no extra setup is needed.

**Option 1: HTTPS (e.g. GitHub PAT)**

```bash
cat > /tmp/.git-credentials <<EOF
https://GITHUB_USERNAME:GITHUB_TOKEN@github.com
EOF

cat > /tmp/.gitconfig <<EOF
[credential]
  helper = store
[user]
  name = Tekton Pipeline
  email = tekton@openshift.local
EOF

oc create secret generic gitops-git-credentials \
  --from-file=.git-credentials=/tmp/.git-credentials \
  --from-file=.gitconfig=/tmp/.gitconfig \
  -n janine-dev

rm -f /tmp/.git-credentials /tmp/.gitconfig
```

**Option 2: SSH**

```bash
oc create secret generic gitops-git-credentials \
  --from-file=id_rsa=/path/to/private/key \
  --from-file=id_rsa.pub=/path/to/public/key \
  --from-file=known_hosts=/path/to/known_hosts \
  -n janine-dev
```

### Deploy Pipeline and Run

```bash
# Apply pipeline
oc apply -f coco_pipeline/pipeline-coco.yaml

# Create a run (edit pipelinerun-coco.yaml to set app-repo-url and source-manifest if needed)
oc apply -f coco_pipeline/pipelinerun-coco.yaml

# Watch run
tkn pipelinerun logs -f coco-pipeline-run -n janine-dev
```

## Pipeline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `cococtl-repo-url` | `https://github.com/confidential-devhub/cococtl` | cococtl Git repository URL |
| `cococtl-branch` | `main` | Branch to clone and build |
| `app-repo-url` | `https://github.com/rh-summit-coco/hospital-demo-gitops-public.git` | App repository URL (requires auth) |
| `app-repo-branch` | `main` | App repository branch |
| `source-manifest` | `application/deid-roberta/templates/deployment.yaml` | Manifest path in the app repo (relative to clone root) |
| `target-manifest-dir` | `application/deid-roberta/manifests` | Output directory for generated manifests (git push target) |
| `runtime-class` | `kata-remote` | CoCo runtime class |
| `trustee-namespace` | `trustee-operator-system` | Trustee operator namespace |
| `sidecar-image` | `quay.io/confidential-devhub/coco-secure-access-sidecar:latest` | CoCo secure access sidecar image |
| `beacon-sidecar-image` | `quay.io/confidential-devhub/attestation-collector-sidecar-secure:latest` | Beacon / attestation sidecar image |

Override any of these in the PipelineRun or when triggering the pipeline.

## Workspaces

- **shared-ws** – PVC (e.g. 5Gi). Holds: cococtl clone and binary, app repo clone, `.kube/config`, coco config and certs. All tasks use this.
- **git-credentials-ws** – Optional. Secret `gitops-git-credentials` (same as build pipeline GitOps update). Used by **pull-repo** for SSH or HTTPS auth.

## Requirements

- OpenShift cluster with Tekton Pipelines
- Namespace `janine-dev` (or adjust namespace in all YAMLs)
- ServiceAccount `pipeline` with cluster access (used for auth-cluster and run-cococtl)
- **ClusterRoleBinding** `pipeline-list-nodes` applied so the pipeline SA can list nodes (cococtl needs this for node IP auto-detection)
- Secret `gitops-git-credentials` for the app repo (same format as for update-gitops)
- App repo must contain the manifest file specified by `source-manifest` (e.g. `application/deid-roberta/templates/deployment.yaml`)
- CoCo / Trustee setup on the cluster as expected by cococtl (runtime class, trustee namespace, etc.)

## Troubleshooting

### pull-cococtl fails (clone or build)

- Check network from the cluster to GitHub.
- Confirm branch `main` exists in `confidential-devhub/cococtl`.
- If the binary is built to a different path (e.g. `_output/bin/kubectl-coco`), the task or **run-cococtl** may need to be updated to use that path.

### pull-repo fails (auth)

- Ensure `gitops-git-credentials` exists and is bound to `git-credentials-ws` in the PipelineRun.
- For HTTPS: secret must include `.git-credentials` and `.gitconfig`.
- For SSH: secret must include `id_rsa`, `id_rsa.pub`, and `known_hosts`.
- Verify the token or key has access to the repo and branch set in `app-repo-url` / `app-repo-branch`.

### auth-cluster fails

- PipelineRun must use `serviceAccountName: pipeline` (or an SA with in-cluster API access).
- If `oc` download from the mirror fails, check cluster egress and the OpenShift client URL in `task-auth-cluster.yaml`.

### run-cococtl fails: "nodes is forbidden" / "failed to auto-detect node IPs"

cococtl runs `kubectl get nodes` to auto-detect node IPs. The pipeline SA needs cluster-scoped permission to list nodes:

```bash
oc apply -f coco_pipeline/clusterrolebinding-pipeline-nodes.yaml
```

Then re-run the pipeline.

### run-cococtl fails (binary or manifest not found)

- **Binary:** Ensure **pull-cococtl** completed and the binary is at `shared-ws/cococtl/kubectl-coco`. If your `make build` puts it elsewhere, adjust the path in **task-run-cococtl**.
- **Manifest:** Ensure **pull-repo** cloned the repo into `shared-ws/app-repo` and that `source-manifest` (e.g. `application/deid-roberta/templates/deployment.yaml`) exists under that directory.
- **Cluster:** Ensure kubeconfig was written by **auth-cluster** at `shared-ws/.kube/config` and that the pipeline SA has RBAC to create the resources cococtl applies.

### Inspecting logs

```bash
# List runs
tkn pipelinerun list -n janine-dev

# Logs for a specific run
tkn pipelinerun logs coco-pipeline-run -n janine-dev

# Logs for a single task
tkn taskrun list -n janine-dev
oc logs -n janine-dev <taskrun-pod-name> -c step-run-init-and-apply
```
