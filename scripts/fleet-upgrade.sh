#!/usr/bin/env bash
# Upgrade Kubernetes (and/or node images) on the member clusters of ONE WAVE of a continent's fleet, by
# creating and starting a Fleet update run with that wave's single-stage update strategy. Run wave-1, watch
# it (Grafana / flux commit statuses), then wave-2, then wave-3. Auto-upgrade is off, so nothing moves on
# its own. "-w waves" runs the full staged strategy (wave-1 -> bake -> wave-2 -> bake -> wave-3) in one go.
#
#   scripts/fleet-upgrade.sh -c na -w wave-1 -v 1.33.2            # control plane + nodes to 1.33.2
#   scripts/fleet-upgrade.sh -c na -w wave-2 -v 1.33.2
#   scripts/fleet-upgrade.sh -c na -w wave-1 --node-image           # node image only, no k8s version change
#   scripts/fleet-upgrade.sh -c na -w wave-1 -v 1.33.2 --no-wait    # create+start, don't poll
#   scripts/fleet-upgrade.sh -c na --status                         # list runs and their state
set -euo pipefail

ENV=dev CONTINENT="" WAVE="" VERSION="" TYPE=Full WAIT=true STATUS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e) ENV=$2; shift 2 ;;
    -c) CONTINENT=$2; shift 2 ;;
    -w) WAVE=$2; shift 2 ;;
    -v) VERSION=$2; shift 2 ;;
    --node-image) TYPE=NodeImageOnly; shift ;;
    --no-wait) WAIT=false; shift ;;
    --status) STATUS=true; shift ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n $CONTINENT ]] || { echo "-c <continent> is required" >&2; exit 1; }
az extension show -n fleet >/dev/null 2>&1 || az extension add -n fleet --only-show-errors

read -r FLEET RG < <(az fleet list --query "[?tags.project=='adtech' && tags.env=='$ENV' && tags.continent=='$CONTINENT'] | [0].[name,resourceGroup]" -o tsv)
[[ -n ${FLEET:-} ]] || { echo "no fleet for env=$ENV continent=$CONTINENT" >&2; exit 1; }

if $STATUS; then
  az fleet updaterun list -g "$RG" -f "$FLEET" -o table \
    --query "[].{name:name, status:status.status.state, started:status.status.startTime, strategy:strategy.stages[0].name}"
  exit 0
fi

[[ -n $WAVE ]] || { echo "-w wave-1|wave-2|wave-3|waves is required" >&2; exit 1; }
if [[ $TYPE == Full ]]; then
  [[ -n $VERSION ]] || { echo "-v <kubernetes-version> is required (or --node-image)" >&2; exit 1; }
  RUN="${WAVE}-k8s-${VERSION//./-}-$(date +%Y%m%d%H%M)"
  VERSION_ARGS=(--kubernetes-version "$VERSION")
else
  RUN="${WAVE}-nodeimage-$(date +%Y%m%d%H%M)"
  VERSION_ARGS=()
fi

echo "==> $FLEET: creating update run $RUN (strategy=$WAVE, type=$TYPE)"
az fleet updaterun create -g "$RG" -f "$FLEET" -n "$RUN" --only-show-errors \
  --update-strategy-name "$WAVE" --upgrade-type "$TYPE" --node-image-selection Latest "${VERSION_ARGS[@]}" >/dev/null
echo "==> starting"
az fleet updaterun start -g "$RG" -f "$FLEET" -n "$RUN" --only-show-errors >/dev/null
$WAIT || { echo "started; watch with: $0 -c $CONTINENT --status"; exit 0; }

while :; do
  state=$(az fleet updaterun show -g "$RG" -f "$FLEET" -n "$RUN" --query status.status.state -o tsv)
  echo "    $(date +%H:%M:%S) $state"
  case $state in
    Completed) exit 0 ;;
    Failed|Stopped) az fleet updaterun show -g "$RG" -f "$FLEET" -n "$RUN" --query status -o yaml; exit 1 ;;
  esac
  sleep 60
done
