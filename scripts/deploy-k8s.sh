#!/usr/bin/env bash
# Push the Fleet HUB baseline (helmfile) to every hub. Member clusters are NOT touched here: they run Flux
# and follow k8s/base + k8s/waves on their own.
#
#   scripts/deploy-k8s.sh [-e dev] [-c na] [helmfile-cmd]     (helmfile-cmd defaults to "diff")
set -euo pipefail

ENV=dev CONTINENT="" CMD=diff
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e) ENV=$2; shift 2 ;;
    -c) CONTINENT=$2; shift 2 ;;
    -h|--help) sed -n 2,6p "$0"; exit 0 ;;
    *) CMD=$1; shift ;;
  esac
done

for bin in az kubelogin helmfile jq; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KUBEDIR=$(mktemp -d)
trap 'rm -rf "$KUBEDIR"' EXIT

filter="tags.project=='adtech' && tags.env=='$ENV'"
[[ -n $CONTINENT ]] && filter+=" && tags.continent=='$CONTINENT'"

az fleet list --query "[?$filter].{name:name, rg:resourceGroup, continent:tags.continent}" -o json |
  jq -c '.[]' | while read -r f; do
    name=$(jq -r .name <<<"$f"); rg=$(jq -r .rg <<<"$f"); continent=$(jq -r .continent <<<"$f")
    echo "==> hub $name"
    kc="$KUBEDIR/$name"
    az fleet get-credentials -g "$rg" -n "$name" --file "$kc" --overwrite-existing --only-show-errors
    KUBECONFIG="$kc" kubelogin convert-kubeconfig -l azurecli
    KUBECONFIG="$kc" helmfile -f "$ROOT/k8s/helmfile.yaml.gotmpl" -e "$ENV" --state-values-set "continent=$continent" "$CMD"
  done
