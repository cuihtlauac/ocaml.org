#─────────────────────────────────────────────────────────────────────────────
# Build system configuration
#
# This project supports two build workflows:
#   1. dune pkg (default) - uses prebuilt dune binary
#   2. opam switch        - uses dune from opam
#
# Dune resolution order:
#   1. Use opam switch if _opam/ exists
#   2. Download prebuilt binary if available for this platform
#   3. Fall back to opam switch (auto-created)
#
# Version constraints:
#   - DUNE_VERSION must be >= (lang dune ...) in dune-workspace
#   - OPAM_REPO_PIN should contain a compatible dune version
#   - When updating OPAM_REPO_PIN, review DUNE_VERSION for consistency
#─────────────────────────────────────────────────────────────────────────────
DUNE_VERSION := 3.21.0
OPAM_REPO_PIN := 584630e7a7e27e3cf56158696a3fe94623a0cf4f

# --- Dune binary download configuration ---
DUNE_BIN_DIR := .dune-bin
DUNE_BIN := $(DUNE_BIN_DIR)/dune

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Platform detection - empty DUNE_PLATFORM if no prebuilt available
ifeq ($(UNAME_S),Linux)
  ifeq ($(UNAME_M),x86_64)
    DUNE_PLATFORM := x86_64-unknown-linux-musl
  endif
else ifeq ($(UNAME_S),Darwin)
  ifeq ($(UNAME_M),arm64)
    DUNE_PLATFORM := aarch64-apple-darwin
  else ifeq ($(UNAME_M),x86_64)
    DUNE_PLATFORM := x86_64-apple-darwin
  endif
endif

DUNE_TARBALL := dune-$(DUNE_VERSION)-$(DUNE_PLATFORM).tar.gz
DUNE_URL := https://github.com/ocaml-dune/dune-bin/releases/download/$(DUNE_VERSION)/$(DUNE_TARBALL)

# --- Build system selection ---
OPAM_SWITCH := $(wildcard _opam)

ifdef OPAM_SWITCH
  # Existing opam switch - use it
  DUNE := opam exec -- dune
  IGNORE_LOCK := --ignore-lock-dir
  DUNE_DEP :=
else ifdef DUNE_PLATFORM
  # Prebuilt available for this platform - will try to download
  DUNE := ./$(DUNE_BIN)
  IGNORE_LOCK :=
  DUNE_DEP := ensure-dune
else
  # No prebuilt for this platform - fall back to opam
  DUNE := opam exec -- dune
  IGNORE_LOCK := --ignore-lock-dir
  DUNE_DEP := ensure-opam-switch
endif

# --- Dune installation targets ---

.PHONY: ensure-dune
ensure-dune:
	@if [ -x "$(DUNE_BIN)" ]; then exit 0; fi; \
	if [ -d _opam ]; then exit 0; fi; \
	mkdir -p $(DUNE_BIN_DIR); \
	echo "Downloading dune $(DUNE_VERSION) for $(DUNE_PLATFORM)..."; \
	if curl -fsSL --retry 2 "$(DUNE_URL)" | tar -xzf - -C $(DUNE_BIN_DIR) 2>/dev/null; then \
	  ln -sf dune-$(DUNE_VERSION)-$(DUNE_PLATFORM)/bin/dune $(DUNE_BIN_DIR)/dune; \
	  echo "Downloaded prebuilt dune."; \
	else \
	  echo "Download failed. Falling back to opam..."; \
	  rm -rf $(DUNE_BIN_DIR); \
	  $(MAKE) switch; \
	fi

.PHONY: ensure-opam-switch
ensure-opam-switch:
	@if [ -d _opam ]; then exit 0; fi; \
	echo "No prebuilt dune for $(UNAME_S)/$(UNAME_M). Creating opam switch..."; \
	$(MAKE) switch

# --- Main targets ---

.DEFAULT_GOAL := all

.PHONY: all
all: $(DUNE_DEP)
	@# Re-evaluate after ensure-* may have created _opam
	@if [ -d _opam ]; then \
	  opam exec -- dune build --root . --ignore-lock-dir; \
	else \
	  ./$(DUNE_BIN) pkg lock; \
	  ./$(DUNE_BIN) build --root .; \
	fi

.PHONY: build
build: all

.PHONY: playground
playground:
	make build -C playground

.PHONY: install
install: all ## Install the packages on the system
	@if [ -d _opam ]; then \
	  opam exec -- dune install --root . --ignore-lock-dir; \
	else \
	  ./$(DUNE_BIN) install --root .; \
	fi

.PHONY: start
start: all ## Run the produced executable
	@if [ -d _opam ]; then \
	  opam exec -- dune exec --ignore-lock-dir src/ocamlorg_web/bin/main.exe; \
	else \
	  ./$(DUNE_BIN) exec src/ocamlorg_web/bin/main.exe; \
	fi

.PHONY: test
test: $(DUNE_DEP) ## Run the unit tests
	@if [ -d _opam ]; then \
	  opam exec -- dune build --root . --ignore-lock-dir @runtest; \
	else \
	  ./$(DUNE_BIN) pkg lock; \
	  ./$(DUNE_BIN) build --root . @runtest; \
	fi

.PHONY: clean
clean: ## Clean build artifacts and other generated files
	@if [ -d _opam ]; then \
	  opam exec -- dune clean --root .; \
	elif [ -x "$(DUNE_BIN)" ]; then \
	  ./$(DUNE_BIN) clean --root .; \
	elif command -v dune >/dev/null 2>&1; then \
	  dune clean --root .; \
	fi

.PHONY: doc
doc: $(DUNE_DEP) ## Generate odoc documentation
	@if [ -d _opam ]; then \
	  opam exec -- dune build --root . --ignore-lock-dir @doc; \
	else \
	  ./$(DUNE_BIN) pkg lock; \
	  ./$(DUNE_BIN) build --root . @doc; \
	fi

.PHONY: fmt
fmt: $(DUNE_DEP) ## Format the codebase with ocamlformat
	@if [ -d _opam ]; then \
	  opam exec -- dune build --root . --ignore-lock-dir --auto-promote @fmt; \
	else \
	  ./$(DUNE_BIN) build --root . --auto-promote @fmt; \
	fi

.PHONY: watch
watch: $(DUNE_DEP) ## Watch for the filesystem and rebuild on every change
	@if [ -d _opam ]; then \
	  opam exec -- dune build --ignore-lock-dir @run -w --force --no-buffer; \
	else \
	  ./$(DUNE_BIN) pkg lock; \
	  ./$(DUNE_BIN) build @run -w --force --no-buffer; \
	fi

.PHONY: utop
utop: $(DUNE_DEP) ## Run a REPL and link with the project's libraries
	@if [ -d _opam ]; then \
	  opam exec -- dune utop --root . --ignore-lock-dir . -- -implicit-bindings; \
	else \
	  ./$(DUNE_BIN) utop --root . . -- -implicit-bindings; \
	fi

.PHONY: scrape_ocaml_planet
scrape_ocaml_planet: $(DUNE_DEP) ## Scrape OCaml Planet feeds
	@if [ -d _opam ]; then \
	  opam exec -- dune build --root . --ignore-lock-dir tool/ood-gen/bin/scrape.exe; \
	  opam exec -- dune exec --root . --ignore-lock-dir tool/ood-gen/bin/scrape.exe planet; \
	  opam exec -- dune exec --root . --ignore-lock-dir tool/ood-gen/bin/scrape.exe video; \
	else \
	  ./$(DUNE_BIN) pkg lock; \
	  ./$(DUNE_BIN) build --root . tool/ood-gen/bin/scrape.exe; \
	  ./$(DUNE_BIN) exec --root . tool/ood-gen/bin/scrape.exe planet; \
	  ./$(DUNE_BIN) exec --root . tool/ood-gen/bin/scrape.exe video; \
	fi

.PHONY: scrape_platform_releases
scrape_platform_releases: $(DUNE_DEP) ## Scrape platform releases
	@if [ -d _opam ]; then \
	  opam exec -- dune exec --root . --ignore-lock-dir tool/ood-gen/bin/scrape.exe platform_releases; \
	else \
	  ./$(DUNE_BIN) exec --root . tool/ood-gen/bin/scrape.exe platform_releases; \
	fi

.PHONY: docker
docker: ## Generate docker container
	docker build --network=host -f Dockerfile . -t ocamlorg:latest

# --- Opam workflow setup ---

.PHONY: switch
switch: create_switch deps ## Create an opam switch and install development dependencies
	@echo "Opam workflow enabled. 'make' will now use opam."

.PHONY: create_switch
create_switch: ## Create switch and pinned opam repo
	opam switch create . 5.2.0 --no-install \
	  --repos pin=git+https://github.com/ocaml/opam-repository#$(OPAM_REPO_PIN)

.PHONY: deps
deps: ## Install development dependencies
	opam install -y ocamlformat=0.26.2 ocaml-lsp-server
	opam install -y --deps-only --with-test --with-doc .
