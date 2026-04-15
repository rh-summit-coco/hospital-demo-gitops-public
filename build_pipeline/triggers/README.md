# Tekton Triggers Setup for GitHub Webhooks

This directory contains the Tekton Trigger resources to automatically trigger the pipeline when code is pushed to GitHub.

## Components

1. **TriggerBinding** (`triggerbinding-github.yaml`) - Extracts data from GitHub webhook payload
2. **TriggerTemplate** (`triggertemplate-pipeline.yaml`) - Creates PipelineRuns from trigger events
3. **EventListener** (`eventlistener-github.yaml`) - Listens for webhook events
4. **Route** (`route-eventlistener.yaml`) - Exposes the EventListener endpoint

## Setup Instructions

### 1. Create GitHub Webhook Secret

First, create a secret for GitHub webhook authentication:

```bash
# Generate a random secret
WEBHOOK_SECRET=$(openssl rand -hex 20)

# Create the secret
oc create secret generic github-webhook-secret \
  --from-literal=secret=$WEBHOOK_SECRET \
  -n janine-dev
```

### 2. Apply Trigger Resources

```bash
oc apply -f triggers/
```

### 3. Get the Webhook URL

After applying the Route, get the webhook URL:

```bash
# Get the webhook URL
WEBHOOK_URL=$(oc get route github-listener -n janine-dev -o jsonpath='{.spec.host}')

echo "Webhook URL: https://${WEBHOOK_URL}"
```

### 4. Configure GitHub Webhook

1. Go to your GitHub repository: `https://github.com/confidential-devhub/deid_roberta`
2. Navigate to **Settings** → **Webhooks** → **Add webhook**
3. Configure:
   - **Payload URL**: `https://${WEBHOOK_URL}`
   - **Content type**: `application/json`
   - **Secret**: The value you used when creating `github-webhook-secret`
   - **Events**: Select "Just the push event"
4. Click **Add webhook**

### 5. Verify Setup

Check that the EventListener is running:

```bash
oc get eventlistener -n janine-dev
oc get pods -n janine-dev | grep github-listener
```

### 6. Test the Trigger

Push a commit to your repository:

```bash
git commit --allow-empty -m "Test webhook trigger"
git push
```

Then check if a PipelineRun was created:

```bash
oc get pipelineruns -n janine-dev
```

## How It Works

1. **GitHub Push Event**: When you push code to the repository, GitHub sends a webhook to the EventListener
2. **EventListener**: Receives the webhook and validates it using the secret
3. **TriggerBinding**: Extracts relevant data (commit SHA, repo URL, etc.) from the webhook payload
4. **TriggerTemplate**: Creates a new PipelineRun with the extracted parameters
5. **Pipeline Execution**: The pipeline runs automatically with the new commit

## Customization

### Filter by Branch

To only trigger on specific branches (e.g., `main`), update the EventListener interceptor:

```yaml
- ref:
    name: "cel"
  params:
    - name: "filter"
      value: "body.ref == 'refs/heads/main'"
```

### Use Branch Name as Image Tag

To use the branch name instead of commit SHA, update the TriggerBinding:

```yaml
- name: image-tag
  value: $(body.ref)
```

Then add processing to remove `refs/heads/` prefix in the EventListener.

### Filter by Repository

To only trigger for specific repositories, add a filter:

```yaml
- ref:
    name: "cel"
  params:
    - name: "filter"
      value: "body.repository.full_name == 'confidential-devhub/deid_roberta'"
```

## Troubleshooting

### Check EventListener Logs

```bash
oc logs -n janine-dev -l app=el-github-listener
```

### Check TriggerBinding/Template

```bash
oc get triggerbinding -n janine-dev
oc get triggertemplate -n janine-dev
```

### Test Webhook Manually

```bash
# Get the webhook URL
WEBHOOK_URL=$(oc get route github-listener -n janine-dev -o jsonpath='{.spec.host}')

# Send a test payload (replace SECRET with your webhook secret)
curl -X POST https://${WEBHOOK_URL} \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=..." \
  -d @test-payload.json
```

## Security Notes

- The webhook secret is required to validate GitHub webhooks
- The Route uses TLS termination for secure communication
- Only push events trigger the pipeline (configured in EventListener)
- Consider adding branch/repository filters for production use

