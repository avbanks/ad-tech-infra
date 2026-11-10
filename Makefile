# make validate                  - validate all 107 units (mocks for unapplied dependencies)
# make plan [CONTINENT=na]       - read-only plan against Azure
# make apply-global              - env-wide resources (Prometheus workspace + Grafana); before any continent
# make apply-debug               - single-node practice cluster aks-dev-eus2-debug (not in the fleet)
# make apply CONTINENT=na        - create a continent (fleet + 2 regions x 9 clusters)
# make k8s-check                 - lint charts + render k8s/base for every role as Flux would (no cluster needed)
# make charts-publish [ARGS=-n]  - package k8s/charts/* and push to the env's ACR (what CI does on merge)
# make hub-deploy [ARGS="-c na apply"] - push the fleet-baseline to the hubs (members are Flux-managed)

LIVE      := live/dev
CONTINENT ?=
TG_DIR    := $(if $(CONTINENT),$(LIVE)/$(CONTINENT),$(LIVE))
TG        := terragrunt run --all --provider-cache --non-interactive

.PHONY: generate validate plan apply-global apply-debug apply destroy destroy-global destroy-debug fmt helm-lint k8s-render k8s-check charts-publish hub-deploy

generate:
	cd $(LIVE) && terragrunt stack generate

validate: generate
	cd $(TG_DIR) && $(TG) -- validate

plan: generate
	cd $(TG_DIR) && $(TG) -- plan -lock=false

apply-global: generate
	cd $(LIVE)/global && terragrunt run --all --provider-cache -- apply

apply-debug: generate
	cd $(LIVE)/sandbox && terragrunt run --all --provider-cache -- apply

destroy-debug: generate
	cd $(LIVE)/sandbox && terragrunt run --all --provider-cache -- destroy

apply: generate
	@test -n "$(CONTINENT)" || (echo "set CONTINENT=na|sa|eu|as|af - applying all 90 clusters at once is deliberate-only" && exit 1)
	cd $(TG_DIR) && terragrunt run --all --provider-cache -- apply

destroy: generate
	@test -n "$(CONTINENT)" || (echo "set CONTINENT" && exit 1)
	cd $(TG_DIR) && terragrunt run --all --provider-cache -- destroy

# Destroy continents first: every cluster's DCR association points at the global DCR.
destroy-global: generate
	cd $(LIVE)/global && terragrunt run --all --provider-cache -- destroy

fmt:
	tofu fmt -recursive modules
	terragrunt hcl fmt

# Umbrella charts need their dependencies fetched before lint/template (network: quay.io, helm.vector.dev).
helm-lint:
	for c in k8s/charts/*; do \
	  helm dependency update $$c >/dev/null && \
	  helm lint $$c -f $$c/values.yaml $$( [ -f $$c/values-dev.yaml ] && echo -f $$c/values-dev.yaml ) \
	    --set vnetListener.ipPrefix=10.0.17 --set kafkaBootstrap=10.0.17.250:9094 --set global.kafkaBootstrap=10.0.17.250:9094 || exit 1; \
	done

# Every role x a wave dir: what Flux will apply, with every $${VAR} resolved.
k8s-render:
	for r in ingest kafka flink debug; do \
	  scripts/render-base.sh $$r k8s/waves/dev/na/wave-1 > /dev/null && echo "base/$$r OK" || exit 1; \
	done
	helmfile -f k8s/helmfile.yaml.gotmpl -e dev --state-values-set continent=na template > /dev/null && echo "hub helmfile OK"

k8s-check: helm-lint k8s-render

charts-publish:
	scripts/publish-charts.sh $(ARGS)

hub-deploy:
	scripts/deploy-k8s.sh $(ARGS)
