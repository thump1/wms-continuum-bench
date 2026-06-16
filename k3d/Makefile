CLUSTER  = continuum
NS       = scientific

.PHONY: up down status deploy clean

up:
	k3d cluster create --config cluster.yaml
	@echo "Waiting for nodes..."
	kubectl wait --for=condition=Ready nodes --all --timeout=120s
	$(MAKE) deploy
	@echo ""
	@echo "Cluster k3d-$(CLUSTER) ready.  Context: k3d-$(CLUSTER)"
	@echo "Run Nextflow IoT pipeline with:  cd ../Nextflow && make iot-k8s"

deploy:
	kubectl apply -f manifests/namespace.yaml
	kubectl apply -f manifests/storage.yaml
	kubectl apply -f manifests/rbac.yaml

status:
	@echo "=== Nodes ==="
	kubectl get nodes -L continuum-tier
	@echo ""
	@echo "=== PVC ==="
	kubectl get pvc -n $(NS)
	@echo ""
	@echo "=== Pods ==="
	kubectl get pods -n $(NS) --sort-by=.metadata.creationTimestamp

down:
	k3d cluster delete $(CLUSTER)

clean: down
	rm -rf /tmp/k3d-nf-work
