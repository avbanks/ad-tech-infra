#!/usr/bin/env bash
# Package every chart in k8s/charts and push it to the env's ACR as an
# OCI Helm chart. A version that already exists in the registry is skipped, never overwritten: Flux and the
# waves pin exact versions, so a published version must be immutable. Bump Chart.yaml to ship a change.
#
#   scripts/publish-charts.sh [-r <login-server>] [-n] [chart ...]
#     -r  registry login server (default: az acr list --query "[?tags.project=='adtech']")
#     -n  dry run: package + print what would be pushed
set -euo pipefail

REGISTRY="" DRY=false
while getopts "r:n" o; do case $o in r) REGISTRY=$OPTARG ;; n) DRY=true ;; *) exit 1 ;; esac; done
shift $((OPTIND - 1))

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHARTS=("$@")
[[ ${#CHARTS[@]} -eq 0 ]] && CHARTS=(ama-metrics-settings kafka-stack flink-stack ingest-stack)

if [[ -z $REGISTRY ]]; then
  REGISTRY=$(az acr list --query "[?tags.project=='adtech'] | [0].loginServer" -o tsv)
  [[ -n $REGISTRY ]] || { echo "no ACR tagged project=adtech; pass -r <login-server>" >&2; exit 1; }
fi
$DRY || az acr login -n "${REGISTRY%%.*}" --only-show-errors

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
for c in "${CHARTS[@]}"; do
  dir="$ROOT/k8s/charts/$c"
  ver=$(awk '/^version:/ {print $2}' "$dir/Chart.yaml")
  if ! $DRY && helm show chart "oci://$REGISTRY/charts/$c" --version "$ver" >/dev/null 2>&1; then
    echo "== $c $ver already published, skipping (bump Chart.yaml to release a change)"
    continue
  fi
  echo "== $c $ver"
  helm dependency update "$dir" >/dev/null
  helm package "$dir" -d "$OUT" >/dev/null
  if $DRY; then echo "   would push $OUT/$c-$ver.tgz -> oci://$REGISTRY/charts"; continue; fi
  helm push "$OUT/$c-$ver.tgz" "oci://$REGISTRY/charts"
done
