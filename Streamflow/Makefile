# Makefile for the StreamFlow SWMS POC.
# Mirrors the Nextflow POC targets for direct comparison.
#
# Requires: .venv/bin/streamflow (run `make setup` first)
#
# Override defaults at the command line, e.g.:
#   make iot DEVICES=50 READINGS=100000

SF       ?= .venv/bin/streamflow
OUTDIR   ?= results
LATENCY  ?= 0

.PHONY: help setup setup-patches info hello hello-docker minipipeline iot iot-ssh iot-hybrid \
        iot-k8s iot-k8s-continuum iot-k8s-cloud-only iot-k8s-latency \
        all all-k8s dashboard clean clean-all validate

help:
	@echo "Targets:"
	@echo "  setup              Create venv and install StreamFlow + apply patches"
	@echo "  info               Show StreamFlow version"
	@echo "  validate           Validate all CWL files with cwltool"
	@echo ""
	@echo "  --- Local / Docker ---"
	@echo "  hello              Run 00_hello (no container, local)"
	@echo "  hello-docker       Run 01_hello_docker (Ubuntu container)"
	@echo "  minipipeline       Run 02_minipipeline (multi-stage DAG)"
	@echo "  iot                Run 04_iot_pipeline (Docker, local)"
	@echo "  iot-ssh            Run 04_iot_pipeline (SSH to Ubuntu server)"
	@echo "  iot-hybrid         Run 04_iot_pipeline (Docker local + SSH server)"
	@echo "  all                Run hello, hello-docker, minipipeline, iot"
	@echo ""
	@echo "  --- Kubernetes (k3d) ---"
	@echo "  iot-k8s            Run 04_iot on k8s (all on cloud worker)"
	@echo "  iot-k8s-continuum  Run 04_iot on k8s (edge steps on edge, cloud on cloud)"
	@echo "  iot-k8s-cloud-only Run 04_iot on k8s (cloud node only, no edge pod)"
	@echo "  iot-k8s-latency    Run 05_iot_latency (edge+cloud with simulated WAN delay)"
	@echo "                       Override: LATENCY=200 (ms, default 0)"
	@echo "  all-k8s            Run all three k8s placement scenarios"
	@echo ""
	@echo ""
	@echo "  --- Dashboard ---"
	@echo "  dashboard          Launch Streamlit provenance dashboard (http://localhost:8501)"
	@echo ""
	@echo "  clean              Remove StreamFlow temp files but keep results/"
	@echo "  clean-all          Remove all generated output"

setup:
	python3.12 -m venv .venv
	.venv/bin/pip install streamflow
	$(MAKE) setup-patches

setup-patches:
	.venv/bin/python patches/apply_patches.py

info:
	$(SF) version

validate:
	.venv/bin/cwltool --validate workflows/00_hello.cwl
	.venv/bin/cwltool --validate workflows/01_hello_docker.cwl
	.venv/bin/cwltool --validate workflows/02_minipipeline.cwl
	.venv/bin/cwltool --validate workflows/04_iot_pipeline.cwl
	.venv/bin/cwltool --validate workflows/05_iot_pipeline_latency.cwl

hello:
	$(SF) run streamflow-hello.yml --outdir $(OUTDIR)/hello

hello-docker:
	$(SF) run streamflow-hello-docker.yml --outdir $(OUTDIR)/hello-docker

minipipeline:
	$(SF) run streamflow-minipipeline.yml --outdir $(OUTDIR)/minipipeline

iot:
	$(SF) run streamflow-iot.yml --outdir $(OUTDIR)/iot_pipeline

iot-ssh:
	$(SF) run streamflow-iot-ssh.yml --outdir $(OUTDIR)/iot_pipeline_ssh

iot-hybrid:
	$(SF) run streamflow-iot-hybrid.yml --outdir $(OUTDIR)/iot_pipeline_hybrid

all: hello hello-docker minipipeline iot

# --- Kubernetes (k3d) targets ---

iot-k8s:
	$(SF) run streamflow-iot-k8s.yml --outdir $(OUTDIR)/iot_k8s

iot-k8s-continuum:
	$(SF) run streamflow-iot-k8s-continuum.yml --outdir $(OUTDIR)/iot_k8s_continuum

iot-k8s-cloud-only:
	$(SF) run streamflow-iot-k8s-cloud-only.yml --outdir $(OUTDIR)/iot_k8s_cloud_only

iot-k8s-latency:
	@echo "transfer_latency_ms: $(LATENCY)" > inputs/_latency_override.yml
	@sed 's|settings: inputs/latency-0ms.yml|settings: inputs/_latency_override.yml|' \
		streamflow-iot-k8s-latency.yml > _sf-latency-run.yml
	$(SF) run _sf-latency-run.yml --outdir $(OUTDIR)/iot_k8s_latency_$(LATENCY)ms
	@rm -f _sf-latency-run.yml inputs/_latency_override.yml

all-k8s: iot-k8s iot-k8s-continuum iot-k8s-cloud-only

# --- tc netem latency injection ---

tc-inject:
	@scripts/tc-inject-latency.sh k3d-continuum-agent-1 $(LATENCY)

tc-remove:
	@scripts/tc-remove-latency.sh all

tc-show:
	@scripts/tc-show-latency.sh

iot-k8s-netem:
	@echo "=== tc netem $(LATENCY)ms on edge node ==="
	scripts/tc-inject-latency.sh k3d-continuum-agent-1 $(LATENCY)
	$(SF) run streamflow-iot-k8s-continuum.yml --outdir $(OUTDIR)/iot_k8s_netem_$(LATENCY)ms || \
		(scripts/tc-remove-latency.sh all && exit 1)
	scripts/tc-remove-latency.sh all

dashboard:
	.venv/bin/streamlit run dashboard/app.py --server.headless true

clean:
	rm -rf /tmp/streamflow*
	find . -name ".streamflow" -type d -exec rm -rf {} + 2>/dev/null || true

clean-all: clean
	rm -rf results/* reports/*
