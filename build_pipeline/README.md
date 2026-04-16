# New Pipeline for deid-roberta

This directory contains a simplified CI/CD pipeline for the `deid-roberta` application.

## Pipeline Overview

The `deid-roberta-pipeline` performs the following steps:

1. **Clone Source** - Pulls source code from `https://github.com/confidential-devhub/deid_roberta.git` (main branch)
2. **Source Security Scan** - Scans source code for hardcoded secrets and security issues
3. **Build Container** - Builds the Docker image using buildah
4. **Vulnerability Scan** - Scans the image for vulnerabilities using Clair scanner
5. **Generate SBOM** - Generates Software Bill of Materials (SBOM) in SPDX format
6. **Push to Quay** - Pushes the signed image to `quay.io/confidential-devhub/hospital-janine-app`
7. **Sign Image** - Cryptographically signs the image with Cosign
8. **Update GitOps** - Updates the GitOps repository with the new image digest, triggering ArgoCD to deploy
9. **Publish RVPS** - Publishes reference values to Trustee RVPS for attestation

## Template secrets (edit before apply)

Files under `secrets/` use **`stringData`** with **`TODO: insert your secret`**. Complete the following, then apply:

| File | What to set |
|------|-------------|
| [`secrets/secret-pipeline-dockerconfigjson.yaml`](secrets/secret-pipeline-dockerconfigjson.yaml) | Quay (or other registry) credentials inside `.dockerconfigjson`; set `username`, `password`, and base64 `auth` for `user:password`. |
| [`secrets/secret-gitops-git-credentials.yaml`](secrets/secret-gitops-git-credentials.yaml) | HTTPS Git access: replace the token in `.git-credentials` (and align with [argocd/application-deid-roberta/repository-secret.yaml](../argocd/application-deid-roberta/repository-secret.yaml) if you share one PAT). |
| [`secrets/cosign-secret.yaml`](secrets/cosign-secret.yaml) | PEM content for `priv` and `pub` (e.g. from `cosign generate-key-pair`); you can instead create the secret with `oc create secret generic cosign-key --from-file=...` and skip storing keys in Git. |

Also ensure **`application/deid-roberta/manifests/`** secrets and [`application/trustee/`](../application/trustee/) match your environment (see root [README.md](../README.md#secrets-do-this-before-oc-apply)).

## Files

- `pipeline-deid-roberta.yaml` - Main pipeline definition
- `tasks/` - Directory containing all required Tekton tasks:
  - `task-git-clone.yaml` - Clones source code from Git
  - `task-build-app.yaml` - Builds container images
  - `task-clair-scanner.yaml` - Scans images for vulnerabilities
  - `task-cosign-sign.yaml` - Signs images with Cosign
  - `task-push-app.yaml` - Pushes images to Quay.io
  - `task-update-gitops.yaml` - Updates GitOps repository with image digest

## Usage

### Deploy Tasks First

```bash
# Apply all tasks
oc apply -f tasks/

# Verify tasks are created
oc get tasks -n janine-dev
```

### Add the secret to push

```bash
oc apply -f secrets/secret-pipeline-dockerconfigjson.yaml
```

### Add Git Credentials for GitOps Update

The pipeline automatically updates the GitOps repository with the new image digest. You need to provide Git credentials:

**Option 1: Using GitHub Personal Access Token (HTTPS)**

1. Create a GitHub Personal Access Token with `repo` scope
2. Create the secret:

```bash
# Create .git-credentials file
cat > /tmp/.git-credentials <<EOF
https://GITHUB_USERNAME:GITHUB_TOKEN@github.com
EOF

# Create .gitconfig file
cat > /tmp/.gitconfig <<EOF
[credential]
  helper = store
[user]
  name = Tekton Pipeline
  email = tekton@openshift.local
EOF

# Create the secret
oc create secret generic gitops-git-credentials \
  --from-file=.git-credentials=/tmp/.git-credentials \
  --from-file=.gitconfig=/tmp/.gitconfig \
  -n janine-dev

# Clean up
rm /tmp/.git-credentials /tmp/.gitconfig
```

**Option 2: Using SSH Keys**

```bash
# Create secret with SSH keys
oc create secret generic gitops-git-credentials \
  --from-file=id_rsa=/path/to/private/key \
  --from-file=id_rsa.pub=/path/to/public/key \
  --from-file=known_hosts=/path/to/known_hosts \
  -n janine-dev
```

See [`secrets/secret-gitops-git-credentials.yaml`](secrets/secret-gitops-git-credentials.yaml) for the committed template (edit `TODO` placeholders).

### Add the PVC
```bash
oc apply -f pvc-buildah-storage.yaml
```

### Add the secret to sign TODO:manual

```bash

export COSIGN_PASSWORD=""
./cosign generate-key-pair

oc create secret generic cosign-key --from-file=pub=secrets/cosign.pub --from-file=priv=secrets/cosign.key -n trustee-operator-system
oc create secret generic cosign-key --from-file=pub=secrets/cosign.pub --from-file=priv=secrets/cosign.key -n janine-dev
```

### Add the serviceaccount rbac (Required for Privileged Containers)

The `buildah-redhat` task requires privileged containers. Grant the service account access:

```bash
# Grant privileged SCC access using ClusterRoleBinding (required for SCC)
oc apply -f clusterrolebinding-privileged-scc.yaml

# Verify the cluster role binding
oc get clusterrolebinding pipeline-privileged-scc
```

### Deploy Pipeline

```bash
# Apply the pipeline
oc apply -f pipeline-deid-roberta.yaml

# Verify pipeline is created
oc get pipeline -n janine-dev
```

### Create PipelineRun

Create a PipelineRun to execute the pipeline:

```bash
oc apply -f pipelinerun.yaml

```

## GitOps Integration

The pipeline automatically updates the GitOps repository with the image digest after pushing:

1. After the image is pushed and signed, the pipeline extracts the image digest
2. The `update-gitops` task clones the GitOps repository
3. Updates `application/deployment.yaml` with the new image digest (format: `image@sha256:...`)
4. Commits and pushes the changes to the configured branch
5. ArgoCD automatically detects the change and syncs the deployment

**Configuration:**
- GitOps repo URL: Set via `gitops-repo-url` parameter (default: `https://github.com/rh-summit-coco/hospital-demo-gitops-public.git`)
- Git branch: Set via `gitops-branch` parameter (default: `main`)
- Deployment path: Set via `deployment-path` parameter (default: `application/deployment.yaml`)

## Differences from Original Pipeline

This pipeline is simplified compared to `secure-ci-pipeline`:

- ✅ Includes source security scan (inline task)
- ✅ Includes SBOM generation (inline task)
- ✅ Includes GitOps update task (automatically updates deployment with image digest)
- ✅ Removed add-dockerfile task (assumes Dockerfile exists)
- ✅ Removed secret sealing task
- ✅ Focused on core CI/CD: clone → source scan → build → image scan → SBOM → push → sign → GitOps update → attestation

## Requirements

- OpenShift cluster with Tekton Pipelines operator installed
- ServiceAccount `pipeline` with appropriate permissions
- **Privileged SCC access** for the `pipeline` service account (required for buildah)
- Secret `pipeline-dockerconfigjson` for registry authentication
- Secret `gitops-git-credentials` for Git authentication (to push to GitOps repo)
- Trustee operator configured (for RVPS publishing, optional)

## Troubleshooting

### Error: "Privileged containers are not allowed"

If you see this error when running the pipeline:
```
unable to validate against any security context constraint:
.containers[0].privileged: Invalid value: true: Privileged containers are not allowed
```

The service account doesn't have access to the privileged SCC. Fix it by:

```bash
# Grant privileged SCC access using ClusterRoleBinding (required for SCC)
oc apply -f clusterrolebinding-privileged-scc.yaml

# Verify the cluster role binding
oc get clusterrolebinding pipeline-privileged-scc
```

After applying, retry your PipelineRun.

### GitOps Update Fails

If the GitOps update task fails:

1. **Check Git credentials:**
   ```bash
   oc get secret gitops-git-credentials -n janine-dev
   ```

2. **Verify the secret has correct format:**
   - For HTTPS: Should contain `.git-credentials` and `.gitconfig` files
   - For SSH: Should contain `id_rsa`, `id_rsa.pub`, and `known_hosts` files

3. **Check pipeline logs:**
   ```bash
   oc logs -n janine-dev -l tekton.dev/task=update-gitops --tail=100
   ```

4. **Verify GitOps repository access:**
   - Ensure the GitHub token has `repo` scope
   - Ensure SSH key has write access to the repository
   - Verify the branch name matches the configured `gitops-branch` parameter

