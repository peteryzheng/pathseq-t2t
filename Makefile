# PathSeq-T2T Makefile
# Usage: `make <target>`   e.g., `make install`, `make test`

# -------------------------
# Config (override via env): e.g. BIN_DIR=~/bin make install
# -------------------------
CLI_PATH      ?= src/pathseq-t2t
BIN_DIR       ?= ~/.local/bin
IMAGE_NAME    ?= pathseq-t2t

# Fail fast on pipeline errors in recipe lines
.SHELLFLAGS := -eu -o pipefail -c

# Mark phony targets
.PHONY: help install uninstall lint test docker-build docker-run conda-env clean veryclean

# -------------------------
# Help
# -------------------------
help:
	@echo "Targets:"
	@echo "  install        Install CLI to $(BIN_DIR)"
	@echo "  uninstall      Remove installed CLI symlink"
	@echo "  lint           Run ShellCheck on CLI and lib scripts"
	@echo "  test           Run smoke tests (help screens)"
	@echo "  docker-build   Build Docker image ($(IMAGE_NAME))"
	@echo "  docker-run     Run container and print CLI help"
	@echo "  conda-env      Create all conda environments from envs/*.yml"
	@echo "  clean          Remove pipeline output directory"
	@echo "  veryclean      Clean + remove common temp artifacts"

# -------------------------
# Install / Uninstall
# -------------------------
install: $(CLI_PATH)
	@mkdir -p $(BIN_DIR)
	chmod +x $(CLI_PATH)
	ln -sf $(abspath $(CLI_PATH)) $(BIN_DIR)/pathseq-t2t
	@echo "Installed to $(BIN_DIR)/pathseq-t2t"

uninstall:
	@rm -f $(BIN_DIR)/pathseq-t2t || true
	@echo "Removed $(BIN_DIR)/pathseq-t2t"

# -------------------------
# Lint
# -------------------------
lint:
	@command -v shellcheck >/dev/null || { echo "Please install ShellCheck"; exit 1; }
	shellcheck $(CLI_PATH) lib/*.sh

# -------------------------
# Tests (smoke)
# -------------------------
test: $(CLI_PATH)
	chmod +x $(CLI_PATH)
	./$(CLI_PATH) --help >/dev/null
	./$(CLI_PATH) filter --help >/dev/null
	./$(CLI_PATH) prefilter --help >/dev/null
	./$(CLI_PATH) qcfilter --help >/dev/null
	./$(CLI_PATH) t2tfilter --help >/dev/null
	./$(CLI_PATH) classify --help >/dev/null
	./$(CLI_PATH) assemble --help >/dev/null
	./$(CLI_PATH) binqc --help >/dev/null
	./$(CLI_PATH) binclassify --help >/dev/null
	./$(CLI_PATH) summarize --help >/dev/null
	./$(CLI_PATH) summarize-assembly --help >/dev/null
	@echo "Smoke tests passed."

# -------------------------
# Docker
# -------------------------
docker-build:
	docker build -t $(IMAGE_NAME) .

docker-run:
	docker run --rm -v $(PWD):/data $(IMAGE_NAME) pathseq-t2t --help

# -------------------------
# Conda
# -------------------------
conda-env:
	@command -v mamba >/dev/null 2>&1 || command -v micromamba >/dev/null 2>&1 || \
	  { echo "mamba or micromamba required"; exit 1; }
	$(if $(shell command -v micromamba 2>/dev/null),micromamba,mamba) env create -f envs/main.yml
	$(if $(shell command -v micromamba 2>/dev/null),micromamba,mamba) env create -f envs/metaphlan.yml
	$(if $(shell command -v micromamba 2>/dev/null),micromamba,mamba) env create -f envs/checkm2.yml
	$(if $(shell command -v micromamba 2>/dev/null),micromamba,mamba) env create -f envs/checkv.yml
	$(if $(shell command -v micromamba 2>/dev/null),micromamba,mamba) env create -f envs/gtdbtk.yml
	@echo "All conda environments created."

# -------------------------
# Clean
# -------------------------
clean:
	rm -rf pst2t_output

veryclean: clean
	find . -name "*.log" -o -name "*.tmp" -o -name "*.bz2" -o -name "*.sbi" -o -name "*.bai" | xargs -r rm -f
