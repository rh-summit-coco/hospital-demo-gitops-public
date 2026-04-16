# Hospital demo GitOps

GitOps manifests, Tekton pipelines, and supporting configuration for the **hospital / deid-roberta** demo: building and signing images, deploying with **Argo CD** to OpenShift (including **CoCo** clusters), running **cococtl** for Confidential Containers, and deploying to **Confidential VMs** on Azure and AWS (via **Tekton** on the hub or **Jenkins** with the included `Jenkinsfile`).

## Documentation map

| Area | README |
|------|--------|
| Argo CD (hub vs external cluster, webhooks) | [argocd/README.md](argocd/README.md) |
| Register a CoCo / external cluster with Argo CD | [argocd/setup_coco_cluster/README.md](argocd/setup_coco_cluster/README.md) |
| `deid-roberta` Argo CD Application and repo secret | [argocd/application-deid-roberta/README.md](argocd/application-deid-roberta/README.md) |
| Build pipeline (clone → build → scan → sign → GitOps digest update) | [build_pipeline/README.md](build_pipeline/README.md) |
| Tekton GitHub triggers for the build pipeline | [build_pipeline/triggers/README.md](build_pipeline/triggers/README.md) |
| CoCo pipeline (cococtl init/apply on the cluster) | [coco_pipeline/README.md](coco_pipeline/README.md) |
| Tekton triggers for the CoCo pipeline | [coco_pipeline/triggers/README.md](coco_pipeline/triggers/README.md) |
| CVM pipeline (Azure/AWS confidential VMs, Ansible, Podman) | [cvm_pipeline/README.md](cvm_pipeline/README.md) |

Most YAML targets namespace **`janine-dev`** unless you change the manifests.

## Secrets (do this before `oc apply`)

Template manifests use **`stringData`** with the placeholder **`TODO: insert your secret`**. Replace every placeholder (or overlay with your own secret objects) before applying; otherwise workloads will not authenticate correctly.

| Area | Files to edit | Notes |
|------|----------------|-------|
| Argo CD repo access | [`argocd/application-deid-roberta/repository-secret.yaml`](argocd/application-deid-roberta/repository-secret.yaml) | GitHub PAT or password in `stringData.password` for private repos. |
| Build / Tekton | [`build_pipeline/secrets/secret-pipeline-dockerconfigjson.yaml`](build_pipeline/secrets/secret-pipeline-dockerconfigjson.yaml), [`secret-gitops-git-credentials.yaml`](build_pipeline/secrets/secret-gitops-git-credentials.yaml), [`cosign-secret.yaml`](build_pipeline/secrets/cosign-secret.yaml) | Quay auth JSON; Git HTTPS `.git-credentials` (match Argo token if shared); Cosign PEM `priv` / `pub`. |
| Trustee / app | [`application/trustee/*-secret.yaml`](application/trustee/) | TLS PEMs, Azure connection string, attestation status, Cosign `pub` in `trustee-operator-system`. |
| Workload namespace | [`application/deid-roberta/manifests/deployment-sealed-secrets.yaml`](application/deid-roberta/manifests/deployment-sealed-secrets.yaml) | Collector certs and Azure string; use real PEMs or regenerate **SealedSecrets** if that is your standard. |
| CVM / Tekton tasks | Create cluster secrets referenced by tasks (e.g. `azure-credentials`, `azure-ssh-key`, `aws-credentials-bigrock`, `user-git-credential`) — see [cvm_pipeline/README.md](cvm_pipeline/README.md). | Not stored as files in this repo. |
| GitHub → Jenkins | Repository secret **`JENKINS_API_TOKEN`** in GitHub Actions settings. | Used by [.github/workflows/trigger-jenkins.yml](.github/workflows/trigger-jenkins.yml). |

Keep generated credentials out of Git (see [.gitignore](.gitignore)); use `*-local.yaml` or sealed secrets / external secret operators for production.

## Recommended order of execution

Steps below assume a **hub** cluster where OpenShift GitOps and pipelines run, and a **CoCo** workload cluster managed via GitOps. Adjust names and namespaces to match your environment.

1. **Hub:** Install **OpenShift GitOps** and **OpenShift Pipelines** (and **Tekton Triggers** if you use webhook-triggered pipelines).

2. **Hub:** Install and configure the **Trustee** operator and related components as required by your demo.

3. **Hub:** Edit placeholders in [`application/trustee/`](application/trustee/) (see **Secrets** above), then apply:

   ```bash
   oc apply -f application/trustee
   ```

4. **CoCo cluster:** Install and configure **OSC** (OpenShift Sandboxed Containers / CoCo stack) per your platform docs.

5. **Hub:** Let Argo CD manage the CoCo cluster: follow [argocd/setup_coco_cluster/README.md](argocd/setup_coco_cluster/README.md).

6. **Hub:** Set `stringData.password` in [`argocd/application-deid-roberta/repository-secret.yaml`](argocd/application-deid-roberta/repository-secret.yaml) if the repo is private, then apply the Argo CD `Application` and secret:

   ```bash
   oc apply -f argocd/application-deid-roberta/
   ```

   Details: [argocd/application-deid-roberta/README.md](argocd/application-deid-roberta/README.md).

7. **Hub:** Configure a **GitHub webhook** so Argo CD syncs on push (or rely on polling). See [argocd/README.md](argocd/README.md) and the application README above.

8. **Hub:** Fill in [build_pipeline/secrets/](build_pipeline/secrets/) (`TODO` placeholders), then install the **build pipeline** (tasks, RBAC, pipeline, triggers). See [build_pipeline/README.md](build_pipeline/README.md):

   ```bash
   oc apply -f build_pipeline/secrets
   oc apply -f build_pipeline/tasks
   oc apply -f build_pipeline/pipeline-deid-roberta.yaml
   oc apply -f build_pipeline/clusterrolebinding-privileged-scc.yaml
   oc apply -f build_pipeline/triggers
   ```

9. **Hub:** Configure the **GitHub webhook** for the build pipeline EventListener: [build_pipeline/triggers/README.md](build_pipeline/triggers/README.md).

10. **Hub:** Install the **CoCo pipeline** (cococtl flow) and node-list RBAC:

    ```bash
    oc apply -f coco_pipeline/tasks
    oc apply -f coco_pipeline/pipeline-coco.yaml
    oc apply -f coco_pipeline/clusterrolebinding-pipeline-nodes.yaml
    oc apply -f coco_pipeline/triggers
    ```

11. **Hub:** Configure the **GitHub webhook** for the CoCo pipeline: [coco_pipeline/triggers/README.md](coco_pipeline/triggers/README.md).

12. **Confidential VM (CVM) deployment:** Provision **Azure** and **AWS** confidential VMs, configure them with Trustee guest components, and run the `deid-roberta` workload on the VMs with **Podman** (`kube play`). Full detail, secrets, and manifests live in [cvm_pipeline/README.md](cvm_pipeline/README.md). You can run this flow in either of these ways (or both, if you maintain separate environments):

    - **Tekton (hub):** Apply the CVM tasks, pipeline, and workspaces; register cloud and SSH secrets as described in the CVM README. Optional GitHub-driven runs: manifests under [cvm_pipeline/deployment-triggers/](cvm_pipeline/deployment-triggers/).

    - **Jenkins:** Run [cvm_pipeline/Jenkinsfile](cvm_pipeline/Jenkinsfile) on a RHEL (or compatible) agent with **Azure CLI**, **AWS CLI**, and **Ansible** available; set credentials and parameters per the comments at the top of the Jenkinsfile. To trigger that job from GitHub when this repo changes, use [.github/workflows/trigger-jenkins.yml](.github/workflows/trigger-jenkins.yml) (requires a **self-hosted** GitHub Actions runner with a label matching `runs-on`, and a Jenkins API token in `JENKINS_API_TOKEN`, because the Jenkins controller is typically reachable only from your internal network).
