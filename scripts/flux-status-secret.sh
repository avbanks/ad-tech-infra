#!/usr/bin/env bash
# Create/refresh Secret flux-system/github-status-token on every Flux-managed cluster, using
# `az aks command invoke` (runs kubectl inside the cluster - no kubeconfig needed).
# The token needs "commit status" write on the repo. Flux's Provider "github-status" uses it.
#
#   GITHUB_STATUS_TOKEN=ghp_... scripts/flux-status-secret.sh [-e dev] [-c na]
set -euo pipefail
: "${GITHUB_STATUS_TOKEN:?set GITHUB_STATUS_TOKEN}"

ENV=dev CONTINENT=""
while [[ $# -gt 0 ]]; do case "$1" in -e) ENV=$2; shift 2 ;; -c) CONTINENT=$2; shift 2 ;; *) echo "unknown arg $1" >&2; exit 1 ;; esac; done

filter="tags.project=='adtech' && tags.env=='$ENV' && tags.wave!=null"
[[ -n $CONTINENT ]] && filter+=" && tags.continent=='$CONTINENT'"

az aks list --query "[?$filter].{name:name, rg:resourceGroup}" -o json | jq -c '.[]' | while read -r c; do
  name=$(jq -r .name <<<"$c"); rg=$(jq -r .rg <<<"$c")
  echo "==> $name"
  az aks command invoke -g "$rg" -n "$name" --only-show-errors -o tsv --query logs --command \
    "kubectl -n flux-system create secret generic github-status-token --from-literal=token='$GITHUB_STATUS_TOKEN' --dry-run=client -o yaml | kubectl apply -f -"
done
