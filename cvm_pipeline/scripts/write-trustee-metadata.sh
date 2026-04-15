#!/usr/bin/env bash
# Write ${WORKSPACE}/.cvm/kbs-url and kbs-cert.pem for Jenkins / tooling that mirrors this flow.
# Uses CVM_DEPLOY_TRUSTEE_KBS_URL; if CVM_DEPLOY_TRUSTEE_KBS_CERT is set, uses it, else embedded default PEM.
set -euo pipefail

WORKSPACE="${WORKSPACE:-${1:-}}"
if [[ -z "${WORKSPACE}" ]]; then
  echo "write-trustee-metadata.sh: set WORKSPACE or pass workspace path as first argument" >&2
  exit 1
fi

mkdir -p "${WORKSPACE}/.cvm"

if [[ -n "${CVM_DEPLOY_TRUSTEE_KBS_CERT:-}" ]]; then
  printf '%s\n' "${CVM_DEPLOY_TRUSTEE_KBS_CERT}" > "${WORKSPACE}/.cvm/kbs-cert.pem"
else
  cat <<'CERT' > "${WORKSPACE}/.cvm/kbs-cert.pem"
-----BEGIN CERTIFICATE-----
MIIDcTCCAlmgAwIBAgIQC6RocS5+jO3dztdLL0+EDjANBgkqhkiG9w0BAQsFADA3
MQ8wDQYDVQQKDAZteV9vcmcxJDAiBgNVBAMTG2ticy10cnVzdGVlLW9wZXJhdG9y
LXN5c3RlbTAeFw0yNjAyMDUxNDE3MDZaFw0yNzAyMDUxNDE3MDZaMDcxDzANBgNV
BAoMBm15X29yZzEkMCIGA1UEAxMba2JzLXRydXN0ZWUtb3BlcmF0b3Itc3lzdGVt
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxWsz4ZyRs1gE0QPCZxjs
1J34V74lSEWyLIBKV3JhqeiaeCmfJWQpO8Fvi7Q+Z5DmFFY/wvntYLjobhqh3Tjl
UJn6BlJwYEuW6G31zs0iESjmqSYvup8WilrauYkNzt3llswiYauPuc4LQ8n0s2As
F2dFlq3ZEntmsps5Xd5Qx6IqVRKzonJkKeKft3wJwjMq0z51py+MDuSQZCtpjDNS
cjngFrBkLGGdRzFDtnp0lhLXQCpdXWDAoWdwmPo8171hDF+66w3ZownwkrwC4tec
S2sX42spa5dfZS0jE3jO8DLHgBNyoRdIvzdoIHAbqM+pTO48oLHy0oQyfSObWuHr
kQIDAQABo3kwdzAOBgNVHQ8BAf8EBAMCBaAwDAYDVR0TAQH/BAIwADBXBgNVHREE
UDBOgkxrYnMtc2VydmljZS10cnVzdGVlLW9wZXJhdG9yLXN5c3RlbS5hcHBzLnVt
bDlkOHJqYWRkMDliZjNmMC5lYXN0dXMuYXJvYXBwLmlvMA0GCSqGSIb3DQEBCwUA
A4IBAQAcdJ6VKMZtuh5bCpf6YAuyxJe13H2IIaT6n/Ntgj/MojLQ+AqlPmxW/zTJ
6UYXnbAUy6k6LSUMMit7F3docbdnamH2uF3WNNqrJRH6K17XTYec0BvvzUD1J7AN
HYbM/MONNXiPS5YWYj7SziOhjOqWrCtxQf1RsVDVTsUniWPwy3ysJuoOrkgnbdV8
g/Ubo/wNiPFifKFRcp9KaTERLZQhkeBy7KjA2CR9jNRfswIh5KqKtqeoPhG6POx+
XzP7upcA/F/8bCsGfXjrY0lDmzC8GDT4nBqu2BMr7bB/lLQ4UcAddRByHxy/RzBR
kfBC8si/J/zrJwhHlVKxUuWYjJWj
-----END CERTIFICATE-----
CERT
fi

printf '%s\n' "${CVM_DEPLOY_TRUSTEE_KBS_URL:-}" > "${WORKSPACE}/.cvm/kbs-url"
echo "KBS URL: $(tr -d '\n\r' < "${WORKSPACE}/.cvm/kbs-url")"
