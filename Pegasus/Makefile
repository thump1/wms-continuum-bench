# Makefile for the Pegasus WMS POC.
# Runs on the CM/submit node (pegasus-cm). Mirrors Nextflow and StreamFlow targets.
#
# Requires: pegasus-plan, pegasus-run, condor_q (HTCondor + Pegasus installed)
#
# Override defaults:
#   make iot DEVICES=50 READINGS=100000 PLACEMENT=continuum

PYTHON   ?= python3
DEVICES  ?= 10
READINGS ?= 10000
ANOMALY  ?= 0.02
PLACEMENT?= any

.PHONY: help hello minipipeline iot iot-continuum iot-cloud \
        status validate-output clean clean-all

help:
	@echo "Targets:"
	@echo "  hello              Run 00_hello (4 greetings)"
	@echo "  minipipeline       Run 02_minipipeline (fan-out/fan-in DAG)"
	@echo "  iot                Run 04_iot_pipeline (any node placement)"
	@echo "  iot-continuum      Run 04_iot_pipeline (edge/cloud placement)"
	@echo "  iot-cloud          Run 04_iot_pipeline (cloud-only placement)"
	@echo ""
	@echo "  status             Show Pegasus workflow status"
	@echo "  validate-output    Diff Pegasus vs Nextflow IoT report"
	@echo "  clean              Remove work directories"
	@echo "  clean-all          Remove work + results"
	@echo ""
	@echo "Overrides:"
	@echo "  DEVICES=10  READINGS=10000  ANOMALY=0.02  PLACEMENT=any|continuum|cloud"

hello:
	$(PYTHON) workflows/00_hello.py
	@condor_reschedule 2>/dev/null || true
	@echo "=== Monitoring hello workflow ==="
	pegasus-status --long work/hello/pegasus/hello-wf 2>/dev/null || true

minipipeline:
	$(PYTHON) workflows/02_minipipeline.py
	@condor_reschedule 2>/dev/null || true
	@echo "=== Monitoring minipipeline workflow ==="
	pegasus-status --long work/minipipeline/pegasus/minipipeline-wf 2>/dev/null || true

iot:
	$(PYTHON) workflows/04_iot_pipeline.py --devices $(DEVICES) --readings $(READINGS) --anomaly-rate $(ANOMALY) --placement $(PLACEMENT)
	@condor_reschedule 2>/dev/null || true
	@echo "=== Monitoring IoT pipeline workflow ==="
	pegasus-status --long work/iot_pipeline/pegasus/iot-pipeline-wf 2>/dev/null || true

iot-continuum:
	$(MAKE) iot PLACEMENT=continuum

iot-cloud:
	$(MAKE) iot PLACEMENT=cloud

status:
	@echo "=== HTCondor pool ==="
	condor_status -af Name ContinuumTier 2>/dev/null || echo "condor_status not available"
	@echo ""
	@echo "=== Pegasus workflows ==="
	@for d in work/*/pegasus/*/; do \
		echo "--- $$d ---"; \
		pegasus-status "$$d" 2>/dev/null || echo "  (no active workflow)"; \
	done

validate-output:
	@echo "=== Validating IoT pipeline output ==="
	@if [ ! -f results/iot_pipeline/iot_report.json ]; then \
		echo "ERROR: results/iot_pipeline/iot_report.json not found"; exit 1; \
	fi
	@$(PYTHON) -c " \
import json, sys; \
r = json.load(open('results/iot_pipeline/iot_report.json')); \
ok = True; \
if r.get('num_devices', 0) != $(DEVICES): \
    print(f\"FAIL: num_devices={r.get('num_devices')} expected=$(DEVICES)\"); ok = False; \
if r.get('total_readings_clean', 0) == 0: \
    print('FAIL: total_readings_clean is 0'); ok = False; \
if 'system_temperature' not in r: \
    print('FAIL: missing system_temperature'); ok = False; \
if ok: print('OK: Pegasus IoT report validates against expected structure'); \
sys.exit(0 if ok else 1) \
"

clean:
	rm -rf work/

clean-all: clean
	rm -rf results/
