run: create-cluster tilt
stop: stop-cluster
start: start-cluster

.PHONY: start-cluster
start-cluster:
	@k3d cluster start local-dev

.PHONY: stop-cluster
stop-cluster:
	@k3d cluster stop local-dev

.PHONY: create-cluster
create-cluster:
	@k3d cluster create local-dev \
	  --registry-create local-dev-registry \
		-v $$HOME/.config/gcloud/application_default_credentials.json:/root/.config/gcloud/application_default_credentials.json

.PHONY: destroy-cluster
destroy-cluster:
	@k3d cluster delete local-dev

.PHONY: tilt
tilt:
	tilt up

.PHONY: provision-dashboards
provision-dashboards:
	make -C dashboards/
