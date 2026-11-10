# make validate                  - validate all 107 units (mocks for unapplied dependencies)
# make plan [CONTINENT=na]       - read-only plan against Azure
# make apply-global              - env-wide resources (Prometheus workspace + Grafana); before any continent
# make apply-debug               - single-node practice cluster aks-dev-eus2-debug (not in the fleet)
# make apply CONTINENT=na        - create a continent (fleet + 2 regions x 9 clusters)
<<<<<<< Updated upstream
# make k8s-check                 - lint charts + render helmfile for every role (no cluster needed)
# make k8s-deploy [ARGS="-c na apply"]
=======
# make k8s-check                 - lint charts + render k8s/base for every role as Flux would (no cluster needed)
# make charts-publish [ARGS=-n]  - package k8s/charts/* and push to the env's ACR (what CI does on merge)
# make k8s-upgrade CONTINENT=na WAVE=wave-1 VERSION=1.33.2 - Fleet update run for one wave (auto-upgrade is off)
>>>>>>> Stashed changes

LIVE      := live/dev
CONTINENT ?=
TG_DIR    := $(if $(CONTINENT),$(LIVE)/$(CONTINENT),$(LIVE))
TG        := terragrunt run --all --provider-cache --non-interactive

<<<<<<< Updated upstream
.PHONY: generate validate plan apply-global apply-debug apply destroy destroy-global destroy-debug fmt helm-lint k8s-template k8s-check k8s-deploy
=======
.PHONY: generate validate plan apply-global apply-debug apply destroy destroy-global destroy-debug fmt helm-lint k8s-render k8s-check charts-publish k8s-upgrade
>>>>>>> Stashed changes

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

helm-lint:
	for c in k8s/charts/*; do helm lint $$c --set vnetListener.ipPrefix=10.0.17 --set kafkaBootstrap=10.0.17.250:9094; done

k8s-template:
	for r in ingest kafka flink hub debug; do \
	  helmfile -f k8s/helmfile.yaml.gotmpl -e dev \
	    --state-values-set role=$$r,cell=01,region=eastus2,continent=na,kafkaIpPrefix=10.10.17 template > /dev/null \
	  && echo "helmfile role=$$r OK" || exit 1; \
	done

<<<<<<< Updated upstream
k8s-check: helm-lint k8s-template

k8s-deploy:
	scripts/deploy-k8s.sh $(ARGS)
=======
# Every role x a wave dir: what Flux will apply, with every $${VAR} resolved.
k8s-render:
	for r in ingest kafka flink debug; do \
	  scripts/render-base.sh $$r k8s/waves/dev/na/wave-1 > /dev/null && echo "base/$$r OK" || exit 1; \
	done

k8s-check: helm-lint k8s-render

charts-publish:
	scripts/publish-charts.sh $(ARGS)

k8s-upgrade:
	@test -n "$(CONTINENT)" -a -n "$(WAVE)" -a -n "$(VERSION)" || (echo "set CONTINENT, WAVE (wave-1|wave-2|wave-3|waves) and VERSION" && exit 1)
	scripts/fleet-upgrade.sh -c $(CONTINENT) -w $(WAVE) -v $(VERSION)
>>>>>>> Stashed changes
