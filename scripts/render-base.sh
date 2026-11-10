#!/usr/bin/env bash
# Render k8s/base/<role> exactly as Flux on a cluster would: kustomize build + post-build substitution from
# the wave's versions ConfigMap and the cluster facts Terraform injects. Fails on any unresolved ${VAR}.
#
#   scripts/render-base.sh <role> [wave-dir] [KEY=VAL ...]
#   scripts/render-base.sh kafka k8s/waves/dev/na/wave-2 REGION=eastus2 CELL=02
set -euo pipefail
command -v flux >/dev/null || { echo "flux CLI required (brew install fluxcd/tap/flux)" >&2; exit 1; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROLE=${1:?role}; WAVE=${2:-k8s/waves/dev/na/wave-1}; shift 2 2>/dev/null || shift $#

# Defaults every cluster has; override with KEY=VAL args.
declare -A F=([ENVIRONMENT]=dev [CONTINENT]=na [REGION]=eastus2 [ROLE]="$ROLE" [CELL]=01 [WAVE]=wave-1
              [KAFKA_IP_PREFIX]=10.10.17 [CLUSTER_NAME]="aks-dev-eus2-$ROLE-01"
              [CHART_REGISTRY]=acrmock.azurecr.io [GITOPS_REPO_URL]=https://github.com/avbanks/ad-tech-infra)
for kv in "$@"; do F[${kv%%=*}]=${kv#*=}; done

# versions ConfigMap data -> substitutions (same thing substituteFrom does on the cluster)
while IFS=: read -r k v; do F[$(echo "$k" | xargs)]=$(echo "$v" | xargs); done \
  < <(awk '/^data:/{d=1;next} d && /^  [A-Z_]+:/' "$ROOT/$WAVE/versions.yaml")

subs=""; for k in "${!F[@]}"; do subs+="      $k: \"${F[$k]}\"\n"; done
ks=$(mktemp); trap 'rm -f "$ks"' EXIT
printf 'apiVersion: kustomize.toolkit.fluxcd.io/v1\nkind: Kustomization\nmetadata: { name: platform-role, namespace: flux-system }\nspec:\n  interval: 1m\n  path: ./k8s/base/%s\n  prune: true\n  sourceRef: { kind: GitRepository, name: platform }\n  postBuild:\n    substitute:\n%b' "$ROLE" "$subs" > "$ks"

out=$(flux build kustomization platform-role --kustomization-file "$ks" --path "$ROOT/k8s/base/$ROLE" --dry-run)
if grep -n '\${[A-Z_]*}' <<<"$out"; then echo "unresolved variables above" >&2; exit 1; fi
echo "$out"
