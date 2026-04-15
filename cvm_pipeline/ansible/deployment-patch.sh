#!/bin/bash
# Usage: deployment-patch.sh <deployment.yaml> <sealed-secrets.yaml>
# 1) Patch deployment YAML for Podman (POD_NAME,POD_NAMESPACE,TEE_TYPE, and hostNetwork).
# 2) Replace sealed-secret placeholders in secret YAML (curl KBS URLs, etc.).

set -euo pipefail

DEPLOYMENT_YAML="${1:?deployment yaml path required}"
SECRET_PATH="${2:?secret yaml path required}"

# Replace pod name and TEE_TYPE
if [ -e /dev/sev-guest ]; then
  pod_name="aws-cvm"
  tee_type="snp"
else
  pod_name="azure-cvm"
  tee_type="AzSnpVtpm"
fi
sed -i "0,/name:/{s/name:.*/name: $pod_name/}" "$DEPLOYMENT_YAML"
sed -i \
"/name: TEE_TYPE/{n;s|.*|\                      value: $tee_type|}" \
  "$DEPLOYMENT_YAML"

# Replace namespace
sed -i \
'/- name: POD_NAMESPACE/{n;N;N;s|.*|\                      value: deid-roberta|}' \
  "$DEPLOYMENT_YAML"

# Add hostNetwork: true to spec
sed -i \
  '/spec:/{N;s/spec:\n[[:space:]]*containers:/spec:\
            hostNetwork: true\
            containers:/}' \
  "$DEPLOYMENT_YAML"

# Replace COLLECTOR_URL when not using OpenShift Route
# (Do not fail the script if cert is missing or grep finds no DNS — pipefail + grep exit 1 would abort.)
collector_url=""
if [ -r /etc/trustee-gc/server.crt ]; then
  collector_url=$(openssl x509 -in /etc/trustee-gc/server.crt -text -noout 2>/dev/null | grep DNS | grep -v aroapp | sed 's/^.*DNS://g' | head -n1) || true
fi
if [ -n "$collector_url" ]; then
  sed -i "s|value: https:.*aroapp.io|value: https://$collector_url:8443|" "$DEPLOYMENT_YAML"
fi

# Replace sealed secrets
function replace_secret() {
  local secret_name=$1
  orig_value=$(grep "$secret_name" "$SECRET_PATH" | awk '{print $2}')
  url=$(echo "$orig_value" | \
    base64 -d | \
    sed 's/sealed.fakejwsheader.//;s/.fakesignature//' | \
    base64 -d | \
    jq .name | \
    sed 's/\"kbs:\/\//http:\/\/127.0.0.1:8006\/cdh\/resource/;s/\"//')
  new_value=$(curl -s "$url" | base64 -w 0 | tr -d '\n\r')
  sed -i "s|$secret_name:.*|$secret_name: $new_value|" "$SECRET_PATH"
}

for secret_name in connection-string ca.crt client.crt client.key; do
  replace_secret "$secret_name"
done
