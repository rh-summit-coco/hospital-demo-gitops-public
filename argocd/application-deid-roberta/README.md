# ArgoCD Application for Hospital Janine App

This directory contains ArgoCD configuration to automatically deploy and update the `deid-roberta-app` application.

## Overview

The ArgoCD Application monitors:
1. **Application Folder**: Any changes in the `application/deid-roberta/manifests` folder in the `prod` branch trigger a redeployment (including [`deployment.yaml`](../../application/deid-roberta/manifests/deployment.yaml) and [`deployment-sealed-secrets.yaml`](../../application/deid-roberta/manifests/deployment-sealed-secrets.yaml); edit **`TODO`** placeholders in the latter before sync).

**Note**: The coco pipeline automatically updates the GitOps repository with new image digests after each successful build, which triggers ArgoCD to automatically sync and deploy the new image.

## Components

- `deid-roberta-app.yaml` - ArgoCD Application definition
- `repository-secret.yaml` - Necessary to access this repo (private Git)

### Edit the repository secret

[`repository-secret.yaml`](repository-secret.yaml) uses **`stringData`**. Replace **`TODO: insert your secret`** in `password` with a GitHub personal access token (or password) that can read this repository. For public repos you may still use a token for rate limits. Re-apply after edits:

```bash
oc apply -f argocd/application-deid-roberta/repository-secret.yaml
```

## Setup Instructions

### Prerequisites

1. **GitOps Operator** must be installed in the cluster
2. **oc/kubectl** CLI access to the hub and coco cluster
3. Follow the guide in setup_coco_cluster to allow Argo to be able to access the coco cluster

### Basic Setup (Application Folder Monitoring)

This works out of the box - ArgoCD will automatically sync when changes are made to the `application/` folder:

```bash
# Install GitOps operator

# add the credentials to access the repo if it's private (generate github token)
oc apply -f argocd/application-deid-roberta/repository-secret.yaml

# Give right rbac permissions if you plan to run the application locally
# Remember to change spec:destination:server with https://kubernetes.default.svc
# oc apply -f argocd/hub_trusted/rbac_local_cluster.yaml

# Apply ArgoCD Application (make sure you pushed application/ on git first)
oc apply -f argocd/application-deid-roberta/deid-roberta-app.yaml
```

The application will automatically sync when you push changes to the `application/` folder in the `prod` branch.

### Automatic Image Updates via Pipeline

The build pipeline automatically updates the GitOps repository with new image digests:

1. **Pipeline builds and pushes image** to the container registry
2. **Pipeline extracts image digest** from the pushed image
3. **Pipeline updates `application/deployment.yaml`** with the new image digest (format: `image@sha256:...`)
4. **Pipeline commits and pushes** the changes to the GitOps repository
5. **ArgoCD automatically detects** the change and syncs the deployment

This ensures that ArgoCD always deploys the exact image that was built and pushed by the pipeline, using immutable digests instead of tags.

**Configuration:**
- The pipeline task `update-gitops` handles the GitOps update
- Git credentials are configured in `build_pipeline/secrets/secret-gitops-git-credentials.yaml`
- The pipeline uses the same GitHub credentials as ArgoCD (from `repository-secret.yaml`)

## How It Works

### Application Folder Monitoring

1. ArgoCD watches the `application/` folder in the `prod` branch of the Git repository
2. When changes are detected (commits pushed to the repo), ArgoCD automatically syncs
3. The application is redeployed with the new configuration

## Configuration Details

### ArgoCD Application

- **Source**: `application/` folder in the Git repository (`prod` branch)
- **Destination**: `janine-app` namespace
- **Sync Policy**: Automated with self-healing enabled

## Verification

### Check Application Status

```bash
# View application status
oc get application hospital-janine-app -n openshift-gitops

# View detailed status
oc describe application hospital-janine-app -n openshift-gitops

# View application in ArgoCD UI
# Access ArgoCD UI and navigate to Applications
```

### Check Image Updater

```bash
# View Image Updater logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-image-updater

# Check for image update events
oc get events -n openshift-gitops | grep image-updater
```

### Test the Setup

1. **Test Image Update via Pipeline**:
   ```bash
   # Trigger the build pipeline
   # The pipeline will automatically update the GitOps repo with the new image digest
   # ArgoCD will detect the change and sync automatically
   # Check if deployment was updated with the new digest
   oc get deployment deid-roberta -n janine-app -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

2. **Test Application Folder Update**:
   ```bash
   # Make a change to application/deployment.yaml
   # Commit and push to the repository
   # ArgoCD should automatically detect and sync
   ```

## Troubleshooting

### Application Not Syncing

```bash
# Check application health
oc get application hospital-janine-app -n openshift-gitops -o yaml

# Check sync status
argocd app get hospital-janine-app

# Force refresh
argocd app refresh hospital-janine-app
```

### Deployment Not Restarting

```bash
# Check deployment status
oc get deployment deid-roberta -n janine-app

# Check pod status
oc get pods -n janine-app -l app=deid-roberta

# View deployment events
oc describe deployment deid-roberta -n janine-app
```

## Customization

### Disable Auto-Sync

To manually control when to sync:

```yaml
syncPolicy:
  automated: null  # Remove automated sync
```

## Security Notes

- ArgoCD uses RBAC to control access to applications
- Consider using sealed secrets or external secret management for production
- Git credentials for pipeline updates are stored in `build_pipeline/secrets/secret-gitops-git-credentials.yaml`

