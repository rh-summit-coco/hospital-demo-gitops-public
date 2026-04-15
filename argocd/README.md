# Argo CD (OpenShift GitOps)

This directory holds **Argo CD Application manifests** and supporting docs for deploying the hospital demo from Git. Argo CD runs on the **hub** cluster and can target the **hub** API or a **registered external** cluster (for example a CoCo / Confidential Computing cluster).

## Documentation in this tree

| Topic | Guide |
|--------|--------|
| Register an external cluster so Argo CD can deploy there | [setup_coco_cluster/README.md](setup_coco_cluster/README.md) |
| Deploy the `deid-roberta` app (Janine): apply order, repo secret, verification | [application-deid-roberta/README.md](application-deid-roberta/README.md) |

Start with **setup_coco_cluster** if Argo CD must manage workloads on a cluster other than where it runs; otherwise use **application-deid-roberta** for the concrete `oc apply` steps.

## Repository layout

| Path | Purpose |
|------|---------|
| [`application-deid-roberta/`](application-deid-roberta/) | `Application` CR, repo credentials template (`repository-secret.yaml`). See [application-deid-roberta/README.md](application-deid-roberta/README.md). |
| [`setup_coco_cluster/`](setup_coco_cluster/) | Step-by-step: kubeconfig, `argocd cluster add`, troubleshooting. See [setup_coco_cluster/README.md](setup_coco_cluster/README.md). |
| [`hub_trusted/`](hub_trusted/) | Optional RBAC when the app is deployed **on the same cluster** as Argo CD (`rbac_local_cluster.yaml`). Adjust `destination.server` in the Application to `https://kubernetes.default.svc` if you use this. |

Application manifests that Argo CD syncs live under `application/deid-roberta/manifests` in this repo (see `path` in `application-deid-roberta/deid-roberta-app.yaml`).

## Prerequisites

1. **OpenShift GitOps** (or Argo CD) installed on the hub cluster.
2. **`oc`** / **`kubectl`** access to the hub and, if used, the target cluster.
3. If deploying to an **external** cluster: complete [setup_coco_cluster/README.md](setup_coco_cluster/README.md) so Argo CD has a valid cluster secret and the right `destination.server`.

## GitHub webhook (optional)

To have Argo CD notice new commits without relying only on polling, add a repository webhook.

1. **Resolve the Argo CD API webhook URL** (hub cluster):

   ```bash
   ARGOCD_URL=https://$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')/api/webhook
   echo "ArgoCD URL: $ARGOCD_URL"
   ```

2. **In GitHub**: repository **Settings** → **Webhooks** → **Add webhook**
   - **Payload URL**: the value of `$ARGOCD_URL`
   - **Content type**: `application/json`
   - **SSL verification**: enabled
   - **Events**: push (or as needed)
   - **Active**: enabled

## Manual update (fallback)

To trigger a sync by changing Git, edit the manifests under `application/deid-roberta/manifests` (for example the image in `deployment.yaml`), commit, and push to the branch Argo CD tracks (for example `prod`):

```bash
git add application/deid-roberta/manifests/
git commit -m "Update deployment manifests"
git push origin prod
```

Argo CD will pick up the change according to its sync policy. Image digests can also be updated automatically by the CI pipeline; details are in [application-deid-roberta/README.md](application-deid-roberta/README.md).

## How syncing works

1. Argo CD watches the configured **repo**, **revision**, and **path** in the `Application` spec.
2. On change (webhook, poll, or manual refresh), it reconciles cluster state to Git.
3. With automated sync and self-heal, drift is corrected to match the repo.

## Disable automated sync

To require manual sync only, remove or null out automated sync in the `Application`:

```yaml
syncPolicy:
  automated: null
```

## Security notes

- Use Argo CD **RBAC** and **AppProjects** appropriate for your environment.
- Repository credentials are templated in [`application-deid-roberta/repository-secret.yaml`](application-deid-roberta/repository-secret.yaml) (`stringData`); replace **`TODO: insert your secret`** before apply. Prefer sealed secrets or an external secrets operator for long-lived clusters.
- Pipeline Git credentials: edit [`build_pipeline/secrets/secret-gitops-git-credentials.yaml`](../build_pipeline/secrets/secret-gitops-git-credentials.yaml) (see root [README.md](../README.md#secrets-do-this-before-oc-apply)).
