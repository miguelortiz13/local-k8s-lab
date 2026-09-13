#!/usr/bin/env bash
# Prueba de humo: abre un port-forward temporal al frontend y espera HTTP 200.
set -euo pipefail

CONTEXT="${CONTEXT:-kind-boutique}"
NAMESPACE="${NAMESPACE:-boutique}"
PORT="${PORT:-18080}"
RETRIES="${RETRIES:-30}"

kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward svc/frontend "$PORT:80" > /dev/null 2>&1 &
pf_pid=$!
trap 'kill "$pf_pid" 2> /dev/null || true' EXIT

for ((i = 1; i <= RETRIES; i++)); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" || true)
  if [[ "$code" == "200" ]]; then
    echo "smoke OK: frontend respondió 200 (intento $i)"
    exit 0
  fi
  sleep 2
done

echo "smoke FALLÓ: último código HTTP '$code'" >&2
exit 1
