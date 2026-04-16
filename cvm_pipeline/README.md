# CVM pipeline (Confidential VM deployment)

This directory contains a pipeline to **provision Confidential VMs** (Azure and AWS), **configure** them with Trustee guest components and optional disk encryption, and **deploy** the `deid-roberta` workload on those VMs using Podman (`kube play`). It complements the cluster-focused flow in [`build_pipeline`](../build_pipeline/README.md), which builds the container image and updates GitOps for Argo CD.

## Pipeline overview

The Tekton pipeline `cvm-pipeline` runs the following steps:

1. **Create Azure VM** — Creates or reuses an Azure Confidential VM (CVM) with the expected image and opens ports for the workload.
2. **Create AWS VM** — Creates or reuses an EC2 instance with AMD SEV-SNP enabled and attached data disk.
3. **Configure VMs** — Runs Ansible (`vm-configure.yml`) to install Trustee guest attestation client components, optional encrypted disk setup, and related configuration. Uses the `trustee_attestation_client` role from a configurable Git repo.
4. **Deploy workload** — Runs Ansible (`deploy-k8s-to-podman.yml`) to apply Kubernetes manifests from this repo on the VMs via Podman (defaults: `application/deid-roberta/manifests/deployment.yaml`, sealed secrets, and `deployment-patch.sh`).

An equivalent flow is implemented for **Jenkins** in `Jenkinsfile` (RHEL agent with Azure CLI, AWS CLI, and Ansible installed locally or via tooling). The Jenkinsfile header documents credential IDs and parameters.

**Trustee metadata:** `scripts/write-trustee-metadata.sh` writes KBS URL and certificate files under `.cvm/` for Jenkins (and can be reused elsewhere). Jenkins runs this before the Ansible configure stage when using that path.

## Files

| Path | Purpose |
|------|---------|
| `pipeline-cvm.yaml` | Tekton `Pipeline` definition (`cvm-pipeline`). |
| `pipelinerun-cvm.yaml` | Example `PipelineRun` with workspaces (SSH secret + source PVC). |
| `Jenkinsfile` | Jenkins pipeline mirroring the Tekton stages; includes parameters and credential wiring. |
| `tasks/task-create-azure-vm.yaml` | Azure VM creation (Azure CLI). |
| `tasks/task-create-aws-vm.yaml` | AWS EC2 creation (AWS CLI). |
| `tasks/task-configure-vm.yaml` | Ansible: configure VMs with Trustee guest components. |
| `tasks/task-deploy-workload-vm.yaml` | Ansible: deploy manifests with Podman on VMs. |
| `tasks/task-build-ansible-image.yaml` | Build `cvm-ansible` image (Ansible + buildah) for use by the configure/deploy tasks’ default `ANSIBLE_IMAGE`. |
| `ansible/` | Playbooks (`vm-configure.yml`, `deploy-k8s-to-podman.yml`, `deploy-trustee-server.yml`), `Containerfile`, `deployment-patch.sh`. |
| `scripts/write-trustee-metadata.sh` | Writes KBS URL and PEM for local/Jenkins runs. |
| `deployment-triggers/` | Tekton Triggers: GitHub push → `PipelineRun` for `cvm-pipeline` (filtered paths; see YAML). |

## Usage (Tekton)

Default namespace in the manifests is `janine-dev`; change it to match your project if needed.

### 1. Build the Ansible runner image (if required)

The configure and deploy tasks default to an internal image such as `image-registry.openshift-image-registry.svc:5000/janine-dev/cvm-ansible:latest`. Build and push it first if it does not exist:

```bash
# Review task-build-ansible-image.yaml for required git credentials and workspaces
oc apply -f tasks/task-build-ansible-image.yaml
# Run a TaskRun or include this task in a pipeline; adapt to your registry and namespace
```

### 2. Apply Tasks and Pipeline

```bash
oc apply -f tasks/task-create-azure-vm.yaml
oc apply -f tasks/task-create-aws-vm.yaml
oc apply -f tasks/task-configure-vm.yaml
oc apply -f tasks/task-deploy-workload-vm.yaml

oc apply -f pipeline-cvm.yaml

oc get pipeline -n janine-dev
oc get tasks -n janine-dev
```

### 3. Secrets and workspaces

These secrets are **not** committed as files; create them in the cluster (prefer **`stringData`** in your own overlay YAML, or `oc create secret generic ... --from-literal` / `--from-file`). Names and keys must match the Tasks:

| Secret | Purpose |
|--------|---------|
| **`azure-credentials`** | Azure service principal: `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`. |
| **`azure-ssh-key`** | SSH key for VM access; must include `id_rsa.pub` (and private key if required by your flow). |
| **`aws-credentials-bigrock`** | AWS credentials file for the AWS VM task (see `task-create-aws-vm.yaml`). |
| **`user-git-credential`** | Git HTTPS user/password (or equivalent) for tasks that clone private repos; see `task-configure-vm.yaml` and `task-build-ansible-image.yaml`. |

**Checklist:** Create the secrets above, then create the `azure-ssh-key` binding before running the example `PipelineRun`. Align Git credentials with the same values you use in [`build_pipeline/secrets/secret-gitops-git-credentials.yaml`](../build_pipeline/secrets/secret-gitops-git-credentials.yaml) where applicable.

### 4. Run the pipeline

```bash
oc create -f pipelinerun-cvm.yaml
```

Or use `oc create -f -` with a `generateName` `PipelineRun` and the same workspace bindings.

## GitHub triggers (optional)

Under `deployment-triggers/`:

- `eventlistener-github.yaml` — EventListener for push events (with CEL filters on branch and paths).
- `triggerbinding-github.yaml`, `triggertemplate-cvm-deployment.yaml` — Bind GitHub payloads to a `PipelineRun`.
- `route-eventlistener.yaml` — Expose the listener (adjust for your Ingress/Route setup).

Install Tekton **Triggers**, apply these manifests, register the webhook URL in GitHub, and align secret names with the template.

## Jenkins

1. Create a multibranch or pipeline job that uses `cvm_pipeline/Jenkinsfile` (or repo root with path filter as appropriate).
2. Configure credentials listed in the Jenkinsfile comments (Azure SP, AWS credentials file, SSH key for VMs, optional Trustee KBS cert).
3. Tune parameters (`GIT_BRANCH`, `GIT_URL`, VM names, regions, Trustee URLs, etc.) for your environment.

## Relationship to GitOps and Argo CD

- Workload paths are under `application/deid-roberta/manifests/` (see [`argocd/application-deid-roberta/README.md`](../argocd/application-deid-roberta/README.md)).
- The **build** pipeline updates image digests in Git for cluster deployment; this **CVM** pipeline targets **Podman on confidential VMs**, not the same sync path as Argo CD unless you wire it yourself.

## Requirements

- OpenShift (or Kubernetes) with **Tekton Pipelines** installed; **Tekton Triggers** for webhook-based runs.
- Permissions for the `pipeline` service account (or chosen SA) to run the tasks and create cloud resources per your policy.
- Valid **Azure** and **AWS** credentials and quotas for CVM / SEV-SNP instances.
- SSH access from the CI cluster or Jenkins agent to the VM public IPs (network/security groups).

## Troubleshooting

- **Task failures on cloud APIs** — Verify secrets and subscription/region; ensure resource names in Task params do not conflict with existing VMs in the wrong state.
- **Ansible image pull errors** — Build and push `cvm-ansible` to the registry namespace your tasks reference, or override `ANSIBLE_IMAGE` in the Tasks.
- **Configure VM fails** — Confirm `VM_LIST` IPs are reachable from the runner, SSH key matches `azure-ssh-key`, and Trustee KBS URL/cert are valid if attestation is required.
