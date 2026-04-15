# Coco Pipeline Triggers (GitHub)

Trigger **coco-pipeline** when the GitOps repo receives a push to **main** authored by **tekton@openshift.local** (e.g. after the build pipeline’s update-gitops task pushes).

## Components

- **EventListener** (`eventlistener-github.yaml`) – Listens for GitHub push (validates with same webhook secret as ArgoCD), CEL filter: main branch (and optionally author email)
- **TriggerBinding** (`triggerbinding-github.yaml`) – Maps webhook payload to coco params (app-repo-url from repo, branch from ref)
- **TriggerTemplate** (`triggertemplate-coco-pipeline.yaml`) – Creates a PipelineRun for coco-pipeline
- **Route** (`route-eventlistener.yaml`) – Exposes the EventListener for the webhook
- **RBAC** (`rolebinding-eventlistener-pipeline.yaml`) – Lets the EventListener’s `pipeline` service account create PipelineRuns and PVCs (required or the webhook returns 202 but no PipelineRun is created)

## Apply

```bash
oc apply -f coco_pipeline/triggers/
```

This applies the EventListener, bindings, template, route, and **RBAC**. The RBAC bindings grant the `pipeline` SA the Tekton Triggers EventListener cluster roles so it can create PipelineRuns when the webhook fires.

## Webhook (GitOps repo)

The EventListener **requires** a webhook secret to validate GitHub requests. It uses the **same secret** as the ArgoCD webhook: `github-webhook-secret` in `janine-dev` must contain the same value you use for the ArgoCD webhook in GitHub. You can use that same secret value for both the ArgoCD and coco webhook URLs.

**Important:** The coco listener has a **different URL** than the build pipeline listener. GitHub sends each push to one Payload URL per webhook. To trigger both pipelines, you need **two webhooks** in the repo: one for the build listener (e.g. `github-listener` route) and one for the coco listener (`coco-github-listener` route).

1. Ensure `github-webhook-secret` exists in `janine-dev` with the same secret value as ArgoCD’s webhook (e.g. create it once and reuse for both listeners).
2. In the **GitOps repo** (e.g. hospital-demo-gitops) on GitHub: **Settings** → **Webhooks** → **Add webhook** (a **second** webhook; keep the one that triggers the build pipeline).
   - **Payload URL**: `https://<route-host>` (from `oc get route coco-github-listener -n janine-dev -o jsonpath='https://{.spec.host}'`)
   - **Content type**: application/json
   - **Secret**: same value as ArgoCD webhook (the value stored in `github-webhook-secret`)
   - **Events**: Just the push event

Only pushes to **main** trigger coco-pipeline (CEL filter). Pushes to other branches are ignored by this listener.

## Troubleshooting

If the webhook does not trigger the coco pipeline:

1. **Two webhooks required** – If the **build** listener works but **coco** does not, you likely have only one webhook pointing at the build listener URL. Add a **second** webhook with the coco listener URL so GitHub sends push events to both:
   ```bash
   # Build listener (you probably already have this one)
   oc get route github-listener -n janine-dev -o jsonpath='https://{.spec.host}'

   # Coco listener – add this URL as a second webhook in GitHub
   oc get route coco-github-listener -n janine-dev -o jsonpath='https://{.spec.host}'
   ```
   In GitHub: **Settings** → **Webhooks** → **Add webhook** → Payload URL = coco URL above.

2. **Secret** – The EventListener uses `github-webhook-secret` in `janine-dev`. The webhook secret in GitHub must match:
   ```bash
   oc get secret github-webhook-secret -n janine-dev -o jsonpath='{.data.secret}' | base64 -d; echo
   ```

3. **EventListener / Service** – Tekton creates a service `el-coco-github-listener`. If the route returns 503 or does not resolve, check:
   ```bash
   oc get eventlistener coco-github-listener -n janine-dev
   oc get svc el-coco-github-listener -n janine-dev
   oc get pods -n janine-dev -l eventlistener=coco-github-listener
   oc logs -n janine-dev -l eventlistener=coco-github-listener -c event-listener
   ```

4. **PipelineRun not created** (webhook returns 202 but no PipelineRun):
   - **RBAC** – The EventListener uses the `pipeline` service account to create the PipelineRun. It must be bound to Tekton’s EventListener cluster roles, or creation is denied. Apply:
     ```bash
     oc apply -f coco_pipeline/triggers/rolebinding-eventlistener-pipeline.yaml
     ```
     Then check that the cluster has the expected cluster roles:
     ```bash
     oc get clusterrole tekton-triggers-eventlistener-roles tekton-triggers-eventlistener-clusterroles
     ```
   - **CEL filter** – Only requests that pass the filter create a PipelineRun. Current filter: `body.ref == 'refs/heads/main'` (push to `main` only). If you also filter by author (e.g. `body.head_commit.author.email == 'tekton@openshift.local'`), ensure the push that hits the webhook matches.
   - **EventListener logs** – Failures creating the PipelineRun are logged in the EventListener pod:
     ```bash
     oc logs -n janine-dev -l eventlistener=coco-github-listener -c event-listener --tail=100
     ```
   - **List PipelineRuns** created by the trigger:
     ```bash
     oc get pipelinerun -n janine-dev -l tekton.dev/triggered-by-github=true
     oc describe eventlistener coco-github-listener -n janine-dev
     ```
