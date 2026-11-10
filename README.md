# ad-tech-infra

Multi-region AKS platform for ad-tech event ingestion → Kafka (Strimzi) → Flink, managed with
**Azure Kubernetes Fleet Manager**. IaC: OpenTofu + Terragrunt (stacks). Workloads: Helm + helmfile.

Only `dev` exists so far. It uses cheap SKUs, the Free AKS tier, 1 system node and 1–2 app nodes per cluster.

## Topology

```
                         5 continents x 2 paired regions x 3 cells x 3 roles = 90 AKS clusters
                                  + 5 hubless Fleet Managers (18 members each; upgrades only)

 Fleet: fleet-adtech-dev-na  (no hub)                 update strategies: "wave-1" | "wave-2" | "wave-3"
 ┌───────────────────────────────────────────────┐       (one wave per run, started by hand) and "waves"
 │ eastus2  (vnet 10.10.0.0/16)                  │       (wave-1 --10m--> wave-2 --10m--> wave-3)
 │                                               │
 │  cell 01        cell 02        cell 03        │     Each cell is a self-contained pipeline:
 │ ┌──────────┐   ┌──────────┐   ┌──────────┐    │
 │ │ ingest-01│   │ ingest-02│   │ ingest-03│    │       bidders / SSPs / pixels
 │ │  Vector  │   │   ...    │   │   ...    │    │               │ HTTP (internal LB)
 │ └────┬─────┘   └──────────┘   └──────────┘    │               ▼
 │      ▼ 10.10.17.250:9094                      │        ingest-0N  (Vector: http -> kafka)
 │ ┌──────────┐                                  │               │ internal LB, static IP
 │ │ kafka-01 │  Strimzi, KRaft                  │               ▼
 │ └────┬─────┘                                  │        kafka-0N   (Strimzi Kafka 4.3, KRaft)
 │      ▼                                        │               │
 │ ┌──────────┐                                  │               ▼
 │ │ flink-01 │  Flink operator, session cluster │        flink-0N   (Flink session cluster)
 │ └──────────┘                                  │
 ├───────────────────────────────────────────────┤
 │ centralus (vnet 10.11.0.0/16)  same 9 clusters│
 └───────────────────────────────────────────────┘
```

| Continent | Primary (waves 1-2)  | Secondary (wave 3)| VNets                  |
|-----------|----------------------|-------------------|------------------------|
| na        | eastus2              | centralus         | 10.10/16, 10.11/16     |
| sa        | brazilsouth          | brazilsoutheast ⚠ | 10.20/16, 10.21/16     |
| eu        | uksouth              | ukwest            | 10.30/16, 10.31/16     |
| as        | centralindia         | southindia        | 10.40/16, 10.41/16     |
| af        | southafricanorth     | southafricawest   | 10.50/16, 10.51/16     |

⚠ See [Known blockers](#known-blockers-before-apply).

### Why it's shaped this way

- **One hubless fleet per continent.** A fleet here is only an Azure-side grouping for Kubernetes upgrade orchestration; there is no hub cluster to pay for or patch. Eighteen members per fleet stays well inside Fleet limits, and an upgrade run can only affect one continent.
- **Cells.** `ingest-0N`, `kafka-0N` and `flink-0N` form a unit. Traffic stays inside one cell and one VNet with no cross-cluster service discovery. A broken cell can be drained independently, and you scale out by adding cells.
- **Every cluster has its own state file.** 90 small states means blast radius and lock contention stay small. Terragrunt **stacks** generate the units, so there are no 90 hand-written folders.
<<<<<<< Updated upstream
- **Fleet owns upgrades, the cluster doesn't.** AKS `automatic_upgrade_channel` is off. A Fleet auto-upgrade profile (`Stable`) triggers update runs that follow the paired-regions strategy. Node OS images still self-patch (`NodeImage`).
- **Two delivery paths for Kubernetes config:**
  - *Fleet hub `ClusterResourcePlacement`* handles the cross-cutting baseline every cluster needs (a namespace and a PriorityClass today). It is applied once per continent and can't drift.
  - *helmfile per member* handles role-specific stacks (operators and CRs). It is driven by AKS tags, so the inventory is whatever Azure actually holds.
=======
- **Upgrades are manual and go by wave.** AKS `automatic_upgrade_channel` is off and the Fleet auto-upgrade profile is off (`fleet_auto_upgrade = null`). Each member's Fleet update group is its wave, and the fleet has a single-stage update strategy per wave plus a full `waves` strategy. `scripts/fleet-upgrade.sh -c na -w wave-1 -v 1.33.2` creates and starts a run for one wave; you watch it, then start the next. Node OS images still self-patch (`NodeImage`).
- **One delivery path for Kubernetes config: Flux on every member.** It pulls the cross-cutting baseline (`k8s/base/_common`: namespace, PriorityClass, agent settings, chart registry) plus the role's HelmReleases from `k8s/base/<role>`, and the versions to run from `k8s/waves/<env>/<continent>/<wave>`. Terraform only tells each cluster which wave and role it is; from then on what runs is a git change.
>>>>>>> Stashed changes

### IP plan

- Region VNet: `10.<cidr_index>.0.0/16`. Every region is unique, so pairs can be peered later (e.g. MirrorMaker2).
- Cluster subnet: `10.<cidr_index>.<role_block*16 + cell>.0/24`.
  - ingest = 1–3, kafka = 17–19, flink = 33–35.
  - Adding a role or cell never renumbers existing subnets.
- Pods and services: Azure CNI **Overlay** + Cilium (`192.168.0.0/16`, `172.16.0.0/16`). These ranges are reused in every cluster because they aren't routable on the VNet.
- Kafka's cross-cluster listener is an **internal LB with pinned IPs**:
  - bootstrap = `<kafka subnet>.250:9094`
  - broker N = `.251+N`
  - Terragrunt computes the prefix and stamps it on every cluster in the cell as the `kafkaIpPrefix` tag. helmfile reads it from there.

### Naming

| Thing | Pattern | Example |
|---|---|---|
| AKS cluster / fleet member | `aks-<env>-<region-short>-<role>-<cell>` | `aks-dev-eus2-kafka-02` |
| Regional RG / VNet | `rg-adtech-<env>-<short>` / `vnet-…` | `rg-adtech-dev-eus2` |
| Fleet | `fleet-adtech-<env>-<continent>` | `fleet-adtech-dev-na` |
| State key | `ad-tech-infra/<env>/<continent>/<region>/<unit>` | `ad-tech-infra/dev/na/eastus2/kafka-02/terraform.tfstate` |

## Layout

```
root.hcl                      backend (tfstateabanks, from mock-infra) + azurerm provider
modules/                      plain OpenTofu modules
  network/                    RG, VNet, per-cluster /24 subnets, NSG
  aks-cluster/                AKS (Entra RBAC, overlay+Cilium, workload identity), app pool,
<<<<<<< Updated upstream
                              subnet role assignment, Fleet membership
  fleet/                      Fleet + hub (azapi), paired-region update strategy, auto-upgrade, hub RBAC
=======
                              subnet role assignment, Fleet membership, Flux bootstrap
  flux-bootstrap/             Flux extension + flux configuration (wave + role Kustomizations), AcrPull
  fleet/                      hubless Fleet (azapi), per-wave + full "waves" update strategies, optional auto-upgrade
>>>>>>> Stashed changes
  monitoring/                 global Azure Monitor Workspace, DCE/DCR, recording rules, Managed Grafana
units/                        Terragrunt unit templates (read `values` from the stack)
  network/  fleet/  aks-cluster/  monitoring/
stacks/region/                one region = network + 9 cluster units
live/dev/
  env.hcl                     subscription, SKUs, role sizing, fleet settings
  regions.hcl                 continent -> paired regions + CIDR index
  global/terragrunt.stack.hcl env-wide units (monitoring), applied before any continent
  <na|sa|eu|as|af>/terragrunt.stack.hcl   fleet unit + primary/secondary region stacks
k8s/
<<<<<<< Updated upstream
  helmfile.yaml.gotmpl        one file for all clusters; releases enabled by role
  charts/kafka-cluster        Kafka + KafkaNodePool + KafkaTopics (Strimzi v1 API)
  charts/flink-session        FlinkDeployment session cluster + kafka-endpoints ConfigMap
  charts/fleet-baseline       hub: namespace, PriorityClass, ClusterResourcePlacement
  values/                     upstream chart values (strimzi, cert-manager, flink-operator, vector)
scripts/
  deploy-k8s.sh               discover clusters/hubs by tag -> helmfile per cluster
=======
  charts/kafka-stack          umbrella: Strimzi operator (dep) + Kafka/KafkaNodePool/KafkaTopics
  charts/flink-stack          FlinkDeployment session cluster + kafka-endpoints ConfigMap
  charts/ingest-stack         umbrella: Vector (dep) + HTTP -> Kafka config
  charts/ama-metrics-settings managed Prometheus agent settings (every cluster)
  base/_common                every cluster: baseline ns/PriorityClass, chart HelmRepository, ama-metrics-settings, Flux -> GitHub status
  base/<kafka|flink|ingest|debug>  HelmReleases per role, versions as ${VARS}
  waves/<env>/<continent>/wave-N/versions.yaml   the numbers a promotion edits
scripts/
  publish-charts.sh           package k8s/charts/* -> ACR (immutable versions); CI runs it on merge
  render-base.sh              render k8s/base/<role> exactly as Flux would, no cluster needed
  flux-status-secret.sh       one-time: GitHub token for commit statuses on every cluster
  fleet-upgrade.sh            Kubernetes / node-image upgrade of one wave via a Fleet update run
>>>>>>> Stashed changes
  validate-crs.py             strict validation of rendered CRs against CRD schemas
```

What each role gets:

| Role | Releases |
|---|---|
<<<<<<< Updated upstream
| kafka  | `strimzi-kafka-operator` 1.3.1 → `kafka-cluster` (Kafka 4.3.2, KRaft, 1 dual-role node in dev, RF=1) |
| flink  | `cert-manager` v1.21.3 → `flink-kubernetes-operator` 1.16.1 → `flink-session` (Flink 1.20) |
| ingest | `vector` 0.61.0: HTTP source → Kafka sink, topic picked by `event_type` |
| hub    | `fleet-baseline` (CRP, PickAll) |
=======
| kafka  | `kafka-stack` = Strimzi operator 1.3.1 + Kafka 4.3.2 (KRaft, 1 dual-role node in dev, RF=1) |
| flink  | `cert-manager` v1.21.3 → `flink-kubernetes-operator` 1.16.1 → `flink-stack` (Flink 1.20 session cluster) |
| ingest | `ingest-stack` = Vector 0.61.0: HTTP source → Kafka sink, topic picked by `event_type` |
| debug  | `_common` only |

## Kubernetes delivery

Nothing is pushed to member clusters. Each one runs Flux (AKS extension) with two Kustomizations that
Terraform creates once (`modules/flux-bootstrap`):

| Kustomization | Path | Produces |
|---|---|---|
| `platform-wave` | `k8s/waves/<env>/<continent>/<wave>` | the `versions` ConfigMap in flux-system |
| `platform-role` | `k8s/base/<role>` | the role's HelmReleases, with `${FACTS}` (from Terraform: ENVIRONMENT, REGION, CELL, KAFKA_IP_PREFIX, ...) and `${*_VERSION}` (from the ConfigMap) substituted |

**Waves** are rollout groups, assigned per cluster by Terraform (`units/aks-cluster`) and stamped as the `wave` tag:

| Wave | Members | Promotion |
|---|---|---|
| wave-1 | primary region, cell 01 (ingest/kafka/flink) | automatic |
| wave-2 | primary region, cells 02-03 | PR, after wave-1 bakes |
| wave-3 | secondary region, all cells | PR, after wave-2 bakes |

Whole cells only: a wave never contains kafka-01 without its ingest-01 and flink-01.

**Shipping a change** (chart template, values, upstream bump, a new app):

1. Edit the chart under `k8s/charts/<role>-stack` and bump `version` in its Chart.yaml. Per-env and per-region
   overrides are `values-<env>.yaml` / `values-<region>.yaml` *inside the chart*, so they are versioned too.
2. Merge. CI runs `make k8s-check` and `scripts/publish-charts.sh`, which pushes the new version to ACR.
   Publishing is inert: no cluster changes.
3. Bump the version in `k8s/waves/dev/na/wave-1/versions.yaml`. Within a minute the three cell-01 clusters
   upgrade; Flux posts a commit status `flux/platform-role/<cluster>` when each is healthy.
4. Repeat for wave-2 and wave-3 by PR. Step 3-4 is what Kargo automates (Warehouse on the chart registry,
   a Stage per wave with `git-open-pr` / `git-wait-for-pr`); it is not wired up yet.

**What bypasses the waves.** `k8s/base/**` is read from `main`, so adding or removing a HelmRelease, or
editing `_common`, reaches every cluster of that role on merge. Keep the base to plumbing; anything that
could hurt belongs in a chart. A new HelmRelease needs its `*_VERSION` key in every wave file first (or in the
same PR), or substitution fails on clusters whose wave lacks it.

**Adding an application to a role**: either add it to the role's umbrella chart (one version, promoted with
the brokers), or give it its own chart + a HelmRelease file in `k8s/base/<role>` + a key in the wave files
(own version, promoted independently). For every role, put the HelmRelease in `k8s/base/_common`.

**Chart registry auth**: Flux's HelmRepository uses `provider: azure`; Terraform grants the kubelet
identity AcrPull. Charts are immutable once published (`publish-charts.sh` skips existing versions).
>>>>>>> Stashed changes

## Observability

Azure Managed Prometheus with **one global Azure Monitor Workspace** (`amw-adtech-dev`, eastus2):

- Every AKS cluster enables the metrics add-on (`ama-metrics` in `kube-system`) and gets a DCR association that sends to the shared DCR/DCE. The workspace stores the data, so nothing in the cluster holds state.
- Every series carries a `cluster` label (`aks-dev-eus2-kafka-02`), so one workspace can still be split by region, role and cell. Recording rules (`modules/monitoring/rules/`) are evaluated in Azure across all clusters and keep `cluster` in every aggregation.
- `amg-adtech-dev` (Managed Grafana) reads the workspace. The admin group is Grafana Admin and can also query the workspace directly.
- Only default targets are scraped today (kubelet, cAdvisor, kube-state-metrics, node-exporter, with the minimal ingestion profile). Kafka/Flink/Vector metrics still need chart changes (PodMonitors in the role charts).
- Global rather than per-continent means telemetry from every continent is stored in the US, and one workspace is a shared dependency. Revisit both (residency, blast radius, ingestion limits) before prod.
- Order: `make apply-global` before any continent; `make destroy-global` only after all continents are destroyed.

## Practice cluster

`aks-dev-eus2-debug` (`live/dev/sandbox`, `modules/debug-cluster`) is a single-node cluster for Kubernetes troubleshooting practice.

- It is **not** a fleet member and has its own RG (`rg-adtech-dev-eus2-debug`), VNet (`10.99.0.0/16`) and state. Breaking it can't affect the cells or the fleets' update runs.
- Two pools of `Standard_D2ads_v6`. `system` (1 node) is tainted `CriticalAddonsOnly` and runs only AKS add-ons. `apps` (autoscale 1–2, label `adtech.io/role=apps`) runs your workloads. That's 4–6 vCPU of eastus2's 10 vCPU quota. Patch auto-upgrade is on because Fleet doesn't manage it.
- It sends metrics to the global Prometheus workspace. Tagged `role=debug`: Flux applies `k8s/base/debug`, which is only the platform releases (`ama-metrics-settings`).
- `make apply-debug` / `make destroy-debug`. Settings live in `env.hcl` `debug_cluster`.

## Usage

<<<<<<< Updated upstream
Tools are pinned in `.tool-versions` (OpenTofu 1.13.2, Terragrunt 1.2.0). You also need `helmfile` (plus the helm-diff plugin: `helm plugin install https://github.com/databus23/helm-diff`, or `helmfile init`), `kubelogin`, `az` and `jq`.
=======
Tools are pinned in `.tool-versions` (OpenTofu 1.13.2, Terragrunt 1.2.0). You also need `helm`, `flux` (`brew install fluxcd/tap/flux`, for `make k8s-check`), `kubelogin`, `az` (with the `fleet` extension) and `jq`.
>>>>>>> Stashed changes

```bash
make validate                 # all 106 units, no Azure calls beyond backend init
make plan CONTINENT=na        # read-only plan (dependencies use mock outputs until applied)
<<<<<<< Updated upstream
make apply-global             # Prometheus workspace + Grafana (once, before any continent)
make apply CONTINENT=na       # fleet -> networks -> 18 clusters (refuses without CONTINENT)
make k8s-check                # helm lint + helmfile template for every role, no cluster needed
scripts/deploy-k8s.sh -c na diff
scripts/deploy-k8s.sh -c na apply      # hub first, then Kafka clusters, then ingest/flink
```

=======
make apply-global             # Prometheus workspace + Grafana + chart registry (once, before any continent)
make charts-publish           # push k8s/charts/* to ACR (CI does this on merge; needed before clusters can install)
make apply CONTINENT=na       # fleet -> networks -> 18 clusters, each with Flux pointing at its wave + role
make k8s-check                # helm lint + render k8s/base for every role as Flux would, no cluster needed
scripts/render-base.sh kafka k8s/waves/dev/na/wave-2 REGION=eastus2 CELL=02   # see exactly what one cluster applies
GITHUB_STATUS_TOKEN=... scripts/flux-status-secret.sh -c na   # once: let Flux post commit statuses
make k8s-upgrade CONTINENT=na WAVE=wave-1 VERSION=1.33.2       # Kubernetes upgrade, one wave; then wave-2, wave-3
scripts/fleet-upgrade.sh -c na --status                        # update runs and their state
```

Flux needs to read the repo: for a private repo `export GITOPS_GIT_TOKEN=<read-only PAT>` before `make apply`
(`env.hcl` passes it to the Flux configuration). Order on a fresh env: `apply-global` → `charts-publish` →
`apply CONTINENT=…`.

>>>>>>> Stashed changes
To shrink dev, delete cell blocks from `stacks/region/terragrunt.stack.hcl` and lower `clusters_per_role` in `env.hcl`. Do the same to grow it.

## Known blockers before apply

Checked against subscription `ed60c73d-…` on 2026-11-07:

1. **vCPU quota.** Every region has a **10 vCPU** regional limit.
   - One region at minimum size needs about 36 vCPUs: 9 clusters × 2 nodes × 2 vCPU.
   - Even a single cell (12 vCPUs) doesn't fit.
   - Request ≥ 40 regional vCPUs, plus the DADSv6/DALDSv6 family, per region you plan to apply.
2. **brazilsoutheast** is a restricted region. Every VM SKU is `NotAvailableForSubscription` until Microsoft approves an access request.
   - It is Brazil South's only in-continent partner.
   - Fallback: `chilecentral`, which is open but not an Azure pair.
3. **northeurope** is blocked for this subscription, so EU uses **uksouth/ukwest**, which is also an official pair.
4. Creating the role assignments (subnet Network Contributor, AcrPull) needs Owner or User Access Administrator.

Rough dev cost if everything ran: about 185 small VMs, roughly **$10–12k/month**. Apply one continent at a time and `make destroy` when done.

## Next steps (not in dev yet)

- Prod sizing: separate controller and broker node pools (3+ each), RF=3, availability zones, Standard AKS tier, dedicated tainted pools.
- Cross-region: VNet peering between pairs and Kafka MirrorMaker2 (`KafkaMirrorMaker2`) primary → secondary.
- TLS and SCRAM/mTLS on the Kafka `vnet` listener. Workload identity for Flink checkpoints to ADLS.
- A public ingest edge (Front Door / App Gateway for Containers) in front of the internal Vector LBs.
- App metrics: PodMonitors (`azmonitoring.coreos.com/v1`) plus Strimzi/Flink/Vector exporters, and alert rule groups. The infra is in place; see [Observability](#observability).
- A CI pipeline running `make validate k8s-check`.
