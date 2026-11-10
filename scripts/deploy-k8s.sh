#!/usr/bin/env bash
# Run helmfile against every AKS member cluster and Fleet hub, using Azure tags as the inventory.
#
#   scripts/deploy-k8s.sh [-e dev] [-c na] [-r eastus2] [-R kafka] [--hubs-only|--no-hubs] [helmfile-cmd]
#
# helmfile-cmd defaults to "diff". Examples:
#   scripts/deploy-k8s.sh -c na -R kafka diff
#   scripts/deploy-k8s.sh -c eu apply
#   scripts/deploy-k8s.sh --hubs-only apply
set -euo pipefail

ENV=dev CONTINENT="" REGION="" ROLE="" HUBS=true MEMBERS=true CMD=diff
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e) ENV=$2; shift 2 ;;
    -c) CONTINENT=$2; shift 2 ;;
    -r) REGION=$2; shift 2 ;;
    -R) ROLE=$2; shift 2 ;;
    --hubs-only) MEMBERS=false; shift ;;
    --no-hubs) HUBS=false; shift ;;
    -h|--help) sed -n 2,11p "$0"; exit 0 ;;
    *) CMD=$1; shift ;;
  esac
done

for bin in az kubelogin helmfile jq; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELMFILE="$ROOT/k8s/helmfile.yaml.gotmpl"
KUBEDIR=$(mktemp -d)
trap 'rm -rf "$KUBEDIR"' EXIT

filter="tags.project=='adtech' && tags.env=='$ENV'"
[[ -n $CONTINENT ]] && filter+=" && tags.continent=='$CONTINENT'"

run_helmfile() { # <kubeconfig> <state-values>
  KUBECONFIG="$1" helmfile -f "$HELMFILE" -e "$ENV" --state-values-set "$2" "$CMD"
}

if $HUBS && [[ -z $REGION && ( -z $ROLE || $ROLE == hub ) ]]; then
  az fleet list --query "[?$filter].{name:name, rg:resourceGroup, continent:tags.continent}" -o json |
    jq -c '.[]' | while read -r f; do
      name=$(jq -r .name <<<"$f"); rg=$(jq -r .rg <<<"$f"); continent=$(jq -r .continent <<<"$f")
      echo "==> hub $name"
      kc="$KUBEDIR/$name"
      az fleet get-credentials -g "$rg" -n "$name" --file "$kc" --overwrite-existing --only-show-errors
      KUBECONFIG="$kc" kubelogin convert-kubeconfig -l azurecli
      run_helmfile "$kc" "role=hub,continent=$continent"
    done
fi

if $MEMBERS && [[ $ROLE != hub ]]; then
  [[ -n $REGION ]] && filter+=" && tags.region=='$REGION'"
  [[ -n $ROLE ]] && filter+=" && tags.role=='$ROLE'"
  az aks list --query "[?$filter].{name:name, rg:resourceGroup, role:tags.role, cell:tags.cell, region:tags.region, continent:tags.continent, kafkaIpPrefix:tags.kafkaIpPrefix}" -o json |
    jq -c 'sort_by(.role != "kafka") | .[]' | while read -r c; do   # Kafka first: ingest/flink point at it
      name=$(jq -r .name <<<"$c"); rg=$(jq -r .rg <<<"$c")
      echo "==> $name"
      kc="$KUBEDIR/$name"
      az aks get-credentials -g "$rg" -n "$name" --file "$kc" --overwrite-existing --only-show-errors
      KUBECONFIG="$kc" kubelogin convert-kubeconfig -l azurecli
      run_helmfile "$kc" "$(jq -r '"role=\(.role),cell=\(.cell),region=\(.region),continent=\(.continent),kafkaIpPrefix=\(.kafkaIpPrefix)"' <<<"$c")"
    done
fi
