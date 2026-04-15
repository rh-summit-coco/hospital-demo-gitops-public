# Adding an External Cluster to ArgoCD (CoCo Cluster)

This guide explains how to fetch credentials from another cluster (e.g. a CoCo / Confidential Computing cluster) and register it with ArgoCD so that ArgoCD can deploy and manage applications on that cluster.

## Overview

- **Hub cluster**: The cluster where ArgoCD (OpenShift GitOps) runs. You run the steps from a machine that can talk to this cluster.
- **Target cluster**: The external cluster you want ArgoCD to manage (e.g. a CoCo cluster). You need valid credentials for this cluster.

ArgoCD stores cluster credentials in a Kubernetes Secret in the `openshift-gitops` namespace. Once registered, you can set `destination.server` in your ArgoCD Applications to that cluster’s API URL.

## Prerequisites

- `oc` (or `kubectl`) and, for Method 1, the ArgoCD CLI (`argocd`)
- Access to the **hub cluster** (where ArgoCD runs), with permission to create/update secrets in `openshift-gitops`
- Access to the **target cluster** (e.g. CoCo cluster), with permission to create service accounts and bindings (for the recommended flow)

## Step 1: Fetch credentials from the target cluster

You need a kubeconfig (or equivalent) that can authenticate to the target cluster’s API server. Do this from a machine that already has access to the target cluster.

### 1.1 Log in to the target cluster

```bash
# Log in to the cluster you want ArgoCD to manage (e.g. CoCo cluster)
oc login --server=https://api.<target-cluster-domain>:6443 -u <user> -p <password>

# Or use token
oc login --server=https://api.<target-cluster-domain>:6443 --token=<token>
```

### 1.2 Get the API server URL

```bash
# API server URL (you will need this when adding the cluster to ArgoCD)
oc whoami --show-server
# Example output: https://api.my-coco-cluster.example.com:6443
```

Save this URL; it becomes the **cluster server** (e.g. `destination.server`) in ArgoCD.

### 1.3 Export a kubeconfig for the target cluster

**Option A – Use current context (simplest)**

Your current context already points at the target cluster after `oc login`. Use that kubeconfig file when adding the cluster:

```bash
# Default kubeconfig is ~/.kube/config
# To use a dedicated file for the target cluster (recommended):
oc config view --minify --raw > /tmp/target-cluster-kubeconfig.yaml
```

**Option B – OpenShift install / kubeadmin**

If you have the install directory (e.g. from OpenShift install):

```bash
export KUBECONFIG=<installation_directory>/auth/kubeconfig
cp $KUBECONFIG /tmp/target-cluster-kubeconfig.yaml
```

**Option C – Merge multiple contexts**

If you have several clusters in one kubeconfig:

```bash
# List contexts
oc config get-contexts

# Write only the target context to a file (replace <context-name> with the context for the CoCo cluster)
KUBECONFIG=/tmp/target-cluster-kubeconfig.yaml oc config view --minify --raw --context=<context-name> > /tmp/target-cluster-kubeconfig.yaml
```

### 1.4 Verify the kubeconfig

```bash
export KUBECONFIG=/tmp/target-cluster-kubeconfig.yaml
oc whoami
oc whoami --show-server
oc get nodes
```

Ensure these commands succeed against the target cluster.

---

## Step 2: Register the target cluster with ArgoCD

You can use the ArgoCD CLI (Method A) or create the cluster secret manually (Method B). Both result in a Secret in `openshift-gitops` that ArgoCD uses to connect to the target cluster.

### Method A: Using the ArgoCD CLI (`argocd cluster add`)

This uses your target-cluster kubeconfig to log in, creates a service account on the target cluster (e.g. `argocd-manager`), and registers that cluster in ArgoCD.

1. **Connect the ArgoCD CLI to your hub cluster’s ArgoCD**

   If ArgoCD is on OpenShift and you use port-forward:

   ```bash
   # Use the hub cluster (where ArgoCD runs)
   export KUBECONFIG=~/.kube/config   # or your hub cluster kubeconfig

   # Port-forward ArgoCD server (optional; only if you don’t have a route)
   oc port-forward svc/openshift-gitops-server -n openshift-gitops 8080:443

   # Login (replace URL if you use the route instead)
   argocd login localhost:8080 --insecure
   # Or with route:
   # argocd login $(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}') --insecure
   ```

2. **Add the target cluster**

   Point the CLI at the **target** cluster’s kubeconfig and context:

   ```bash
   # Use the kubeconfig you created for the target cluster
   argocd cluster add <context-name> --kubeconfig /tmp/target-cluster-kubeconfig.yaml --name coco-cluster
   ```

   Replace `<context-name>` with the context name from that kubeconfig (e.g. `default` or the output of `oc config current-context` when `KUBECONFIG=/tmp/target-cluster-kubeconfig.yaml`).

   For OpenShift GitOps on OpenShift, you may need to tell the CLI where ArgoCD runs:

   ```bash
   argocd cluster add <context-name> \
     --kubeconfig /tmp/target-cluster-kubeconfig.yaml \
     --name coco-cluster \
     --core \
     --kube-context <hub-context>
   ```

   Here `<hub-context>` is the context for the **hub** cluster (where ArgoCD is installed).

3. **Confirm**

   When prompted, confirm so that the CLI can create the service account on the target cluster and the secret on the hub.

### Method B: Creating the cluster secret manually

Use this when you cannot run `argocd cluster add` (e.g. no ArgoCD CLI, or you want to use an existing service account token).

1. **Create a service account on the target cluster** (from a session that has admin rights on the target):

   ```bash
   export KUBECONFIG=/tmp/target-cluster-kubeconfig.yaml

   # Create namespace if needed
   oc create namespace openshift-gitops  # or kube-system, or a dedicated namespace

   # Create service account for ArgoCD
   oc create serviceaccount argocd-manager -n openshift-gitops

   # Grant cluster-admin (or a more restricted role) to the service account
   oc create clusterrolebinding argocd-manager-admin \
     --clusterrole=cluster-admin \
     --serviceaccount=openshift-gitops:argocd-manager
   ```

2. **Get the service account token**

   ```bash
   # OpenShift 4.11+: create a token (or use the projected token from the SA)
   oc create token argocd-manager -n openshift-gitops --duration=8760h
   ```

   Copy the token; you will put it in the Secret as `bearerToken` (base64-encoded).

3. **Get the target cluster’s CA certificate** (if you want to verify TLS)

   ```bash
   oc config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
   ```

   If your kubeconfig uses `certificate-authority: /path/to/file`, read that file and base64-encode it.

4. **Create the cluster secret on the hub cluster**

   Switch to the hub cluster and create the Secret in `openshift-gitops`:

   ```bash
   export KUBECONFIG=~/.kube/config   # hub cluster

   # Set variables
   TARGET_SERVER="https://api.<target-cluster-domain>:6443"   # from oc whoami --show-server
   TARGET_NAME="coco-cluster"
   BEARER_TOKEN="<paste-token-here>"
   CA_DATA="<base64-encoded-ca-certificate>"   # optional; omit if using insecure-skip-tls-verify

   oc create secret generic cluster-coco-cluster \
     -n openshift-gitops \
     --from-literal=name=${TARGET_NAME} \
     --from-literal=server=${TARGET_SERVER} \
     --from-literal=config='{"bearerToken":"'${BEARER_TOKEN}'","tlsClientConfig":{"insecureSkipTlsVerify":true}}'
   ```

   To use the CA certificate instead of skipping TLS verification, use:

   ```json
   {"bearerToken":"<token>","tlsClientConfig":{"caData":"<base64-ca>"}}
   ```

   Then label and annotate the secret so ArgoCD picks it up:

   ```bash
   oc label secret cluster-coco-cluster -n openshift-gitops argocd.argoproj.io/secret-type=cluster
   oc annotate secret cluster-coco-cluster -n openshift-gitops argocd.argoproj.io/secret-type=cluster
   ```

   (The exact label/annotation may depend on your ArgoCD/OpenShift GitOps version; `argocd.argoproj.io/secret-type=cluster` is the standard.)

---

## Step 3: Verify the cluster in ArgoCD

**From the ArgoCD UI**

- Open the ArgoCD route (e.g. from the OpenShift console or `oc get route -n openshift-gitops`).
- Go to **Settings → Clusters**. You should see the new cluster (e.g. `coco-cluster`) and its server URL.

**From the CLI**

```bash
argocd cluster list
```

**From the hub cluster**

```bash
oc get secrets -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster
oc get secret cluster-coco-cluster -n openshift-gitops -o yaml   # if you used that name
```

---

## Step 4: Deploy an application to the target cluster

In your ArgoCD Application spec, set `destination.server` to the target cluster’s API URL and choose a namespace on that cluster:

```yaml
spec:
  destination:
    server: https://api.<target-cluster-domain>:6443
    namespace: my-app-namespace
```

Alternatively, if you registered the cluster with a **name** (e.g. `coco-cluster`), you can use that name as the server (ArgoCD resolves it to the URL):

```yaml
spec:
  destination:
    server: coco-cluster
    namespace: my-app-namespace
```

Commit and apply the Application; ArgoCD will use the credentials stored in the cluster secret to sync to the target cluster.

---

## Summary

| Step | Action |
|------|--------|
| 1    | Log in to the target cluster and run `oc whoami --show-server` to get the API URL. |
| 2    | Export a kubeconfig for the target cluster (e.g. `oc config view --minify --raw`). |
| 3    | Either run `argocd cluster add <context> --kubeconfig <file> --name coco-cluster` or create a cluster secret in `openshift-gitops` with server URL, name, and bearer token (and optional CA). |
| 4    | In Applications, set `destination.server` to that URL or cluster name and deploy. |

---

## Troubleshooting

- **“failed to get server version: the server has asked for the client to provide credentials”**  
  ArgoCD is trying to talk to a cluster (e.g. the CoCo cluster) but the credentials in the cluster secret are missing, wrong, or **expired**. OpenShift service account tokens can expire. Fix: get a fresh token from the target cluster and update the secret in `openshift-gitops`:
  1. Log in to the **target** cluster and create a new token (or use an existing SA that has a valid token):
     ```bash
     oc create token argocd-manager -n openshift-gitops --duration=8760h
     ```
  2. On the **hub** cluster, update the cluster secret with the new token (replace `<secret-name>` with the secret name, e.g. `cluster-coco-cluster`):
     ```bash
     oc get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster
     # Edit the secret to set the new bearer token in the config (base64-encoded), or delete and recreate it with the new token.
     ```
  Or re-run `argocd cluster add` with a valid kubeconfig for the target cluster so ArgoCD stores fresh credentials.

- **ArgoCD shows cluster as “Unknown” or connection fails**  
  Check the secret in `openshift-gitops`: correct `server` URL, valid token, and (if used) correct `caData`. Ensure the target cluster is reachable from the hub (network/firewall).

- **OpenShift: “argocd cluster add” fails**  
  Some OpenShift versions or security settings can cause issues. Use Method B (manual secret with a service account token) instead.

- **Certificate / TLS errors**  
  Use the target cluster’s CA in the secret’s `config.tlsClientConfig.caData`, or temporarily use `insecureSkipTlsVerify: true` only for testing.

- **Permission denied on the target cluster**  
  Ensure the service account used by ArgoCD (e.g. `argocd-manager`) has sufficient rights (e.g. `cluster-admin` or a role that can create resources in the target namespaces).
