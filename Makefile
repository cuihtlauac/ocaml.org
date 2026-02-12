#─────────────────────────────────────────────────────────────────────────────
# Configuration
#
# Two build workflows:
#   1. dune-pkg (default) — downloads a prebuilt dune binary
#   2. opam              — uses dune from a local opam switch
#
# If _opam/ exists, the opam workflow is used automatically.
# Run `make switch` to create an opam switch.
#─────────────────────────────────────────────────────────────────────────────

DUNE_VERSION := 3.21.0
OPAM_REPO_PIN := 584630e7a7e27e3cf56158696a3fe94623a0cf4f

# Platform detection for prebuilt dune binary
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

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

DUNE_URL := https://github.com/ocaml-dune/dune-bin/releases/download/$(DUNE_VERSION)/dune-$(DUNE_VERSION)-$(DUNE_PLATFORM).tar.gz

# Mode detection: opam switch vs dune-pkg
OPAM_SWITCH := $(wildcard _opam)

ifdef OPAM_SWITCH
  DUNE      := opam exec -- dune
  DUNE_ARGS := --ignore-lock-dir
  LOCK_DEP  :=
else
  DUNE      := .dune-bin/dune
  DUNE_ARGS :=
  LOCK_DEP  := dune.lock
endif

#─────────────────────────────────────────────────────────────────────────────
# Dune binary download + lock (dune-pkg mode only)
#─────────────────────────────────────────────────────────────────────────────

.dune-bin/dune:
ifdef DUNE_PLATFORM
	@mkdir -p .dune-bin
	@echo "Downloading dune $(DUNE_VERSION) for $(DUNE_PLATFORM)..."
	@curl -fsSL --retry 2 "$(DUNE_URL)" | tar -xzf - -C .dune-bin
	@ln -sf dune-$(DUNE_VERSION)-$(DUNE_PLATFORM)/bin/dune .dune-bin/dune
else
	@echo "Error: No prebuilt dune for $(UNAME_S)/$(UNAME_M). Run 'make switch' for the opam workflow." >&2
	@false
endif

dune.lock: .dune-bin/dune
	$(DUNE) pkg lock

#─────────────────────────────────────────────────────────────────────────────
# Build targets
#─────────────────────────────────────────────────────────────────────────────

.DEFAULT_GOAL := all

.PHONY: all build start watch test clean fmt doc install utop
.PHONY: playground scrape_ocaml_planet scrape_platform_releases docker

all: $(LOCK_DEP)
	$(DUNE) build --root . $(DUNE_ARGS)

build: all

start: all
	$(DUNE) exec $(DUNE_ARGS) src/ocamlorg_web/bin/main.exe

watch: $(LOCK_DEP)
	$(DUNE) build $(DUNE_ARGS) @run -w --force --no-buffer

test: $(LOCK_DEP)
	$(DUNE) build --root . $(DUNE_ARGS) @runtest

fmt: $(LOCK_DEP)
	$(DUNE) build --root . $(DUNE_ARGS) --auto-promote @fmt

doc: $(LOCK_DEP)
	$(DUNE) build --root . $(DUNE_ARGS) @doc

install: all
	$(DUNE) install --root . $(DUNE_ARGS)

clean:
	-$(DUNE) clean --root .

utop: $(LOCK_DEP)
	$(DUNE) utop --root . $(DUNE_ARGS) . -- -implicit-bindings

playground:
	$(MAKE) build -C playground

scrape_ocaml_planet: $(LOCK_DEP)
	$(DUNE) build --root . $(DUNE_ARGS) tool/ood-gen/bin/scrape.exe
	$(DUNE) exec --root . $(DUNE_ARGS) tool/ood-gen/bin/scrape.exe planet
	$(DUNE) exec --root . $(DUNE_ARGS) tool/ood-gen/bin/scrape.exe video

scrape_platform_releases: $(LOCK_DEP)
	$(DUNE) exec --root . $(DUNE_ARGS) tool/ood-gen/bin/scrape.exe platform_releases

docker:
	docker build --network=host -f Dockerfile . -t ocamlorg:latest

#─────────────────────────────────────────────────────────────────────────────
# Opam workflow setup
#─────────────────────────────────────────────────────────────────────────────

.PHONY: switch create_switch deps

switch: create_switch deps ## Create an opam switch and install dependencies
	@echo "Opam workflow enabled. 'make' will now use opam."

create_switch:
	opam switch create . 5.2.0 --no-install \
	  --repos pin=git+https://github.com/ocaml/opam-repository#$(OPAM_REPO_PIN)

deps:
	opam install -y ocamlformat=0.26.2 ocaml-lsp-server
	opam install -y --deps-only --with-test --with-doc .
