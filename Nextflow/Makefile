# Makefile for the Nextflow SWMS POC.
# Common shortcuts for running and cleaning the pipelines.
#
# Override defaults at the command line, e.g.:
#   make hello PROFILE=docker
#   make minipipeline PROFILE=server

NF       ?= nextflow
PROFILE  ?= standard
CHUNKS   ?= 10
CHUNK_MB ?= 25
ROUNDS   ?= 500
DEVICES  ?= 10
READINGS ?= 10000

.PHONY: help info hello hello-docker minipipeline benchmark iot all clean clean-all

help:
	@echo "Targets:"
	@echo "  info           Show Nextflow version and the chosen profile"
	@echo "  hello          Run 00_hello.nf (no container)"
	@echo "  hello-docker   Run 01_hello_docker.nf (Ubuntu container)"
	@echo "  minipipeline   Run 02_minipipeline.nf (multi-stage DAG)"
	@echo "  benchmark      Run 03_benchmark.nf (configurable performance test)"
	@echo "  iot            Run 04_iot_pipeline.nf (IoT sensor continuum workflow)"
	@echo "  all            Run all pipelines in sequence"
	@echo "  clean          Remove work/ but keep results/ and reports/"
	@echo "  clean-all      Remove work/, results/, reports/, .nextflow*"
	@echo ""
	@echo "Variables:"
	@echo "  NF        path to nextflow binary       (default: nextflow)"
	@echo "  PROFILE   nextflow profile to use       (default: standard)"
	@echo "            Available: standard, docker, server, k8s"
	@echo "  CHUNKS    number of parallel chunks     (default: 10)"
	@echo "  CHUNK_MB  size of each chunk in MB      (default: 25)"
	@echo "  ROUNDS    SHA-256 hash iterations/chunk  (default: 500)"
	@echo "  DEVICES   number of IoT devices         (default: 10)"
	@echo "  READINGS  readings per device            (default: 10000)"

info:
	@$(NF) -v
	@$(NF) info
	@echo ""
	@echo "Selected profile: $(PROFILE)"

hello:
	$(NF) run pipelines/00_hello.nf -profile $(PROFILE)

hello-docker:
	$(NF) run pipelines/01_hello_docker.nf -profile docker

minipipeline:
	$(NF) run pipelines/02_minipipeline.nf -profile docker

benchmark:
	$(NF) run pipelines/03_benchmark.nf -profile docker \
		--num_chunks $(CHUNKS) --chunk_size_mb $(CHUNK_MB) --hash_rounds $(ROUNDS)

iot:
	$(NF) run pipelines/04_iot_pipeline.nf -profile docker \
		--num_devices $(DEVICES) --readings_per_device $(READINGS)

iot-native:
	$(NF) run pipelines/04_iot_pipeline.nf -profile standard \
		--num_devices $(DEVICES) --readings_per_device $(READINGS)

iot-k8s:
	$(NF) run pipelines/04_iot_pipeline.nf -profile k8s \
		-w /private/tmp/k3d-nf-work/work \
		--num_devices $(DEVICES) --readings_per_device $(READINGS)

all: hello hello-docker minipipeline benchmark iot

clean:
	rm -rf work/

clean-all: clean
	rm -rf results/ reports/ .nextflow* .nextflow.log*
