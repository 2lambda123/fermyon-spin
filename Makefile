LOG_LEVEL_VAR ?= RUST_LOG=spin=trace
CERT_NAME ?= local
SPIN_DOC_NAME ?= new-doc.md
export PATH := target/debug:target/release:$(HOME)/.cargo/bin:$(PATH)

ARCH = $(shell uname -p)

## dependencies for e2e-tests
E2E_BUILD_SPIN                  ?= false
E2E_FETCH_SPIN                  ?= true
E2E_TESTS_DOCKERFILE            ?= e2e-tests.Dockerfile
MYSQL_IMAGE                     ?= mysql:8.0.22
REDIS_IMAGE                     ?= redis:7.0.8-alpine3.17
POSTGRES_IMAGE                  ?= postgres:14.7-alpine
REGISTRY_IMAGE                  ?= registry:2
E2E_SPIN_RELEASE_VOLUME_MOUNT   ?=
E2E_SPIN_DEBUG_VOLUME_MOUNT     ?=

## overrides for aarch64
ifneq ($(ARCH),x86_64)
	MYSQL_IMAGE             = arm64v8/mysql:8.0.32
	REDIS_IMAGE             = arm64v8/redis:6.0-alpine3.17
	POSTGRES_IMAGE          = arm64v8/postgres:14.7
	REGISTRY_IMAGE          = arm64v8/registry:2
	E2E_TESTS_DOCKERFILE    = e2e-tests-aarch64.Dockerfile
endif

ifneq (,$(wildcard $(shell pwd)/target/release/spin))
	E2E_SPIN_RELEASE_VOLUME_MOUNT = -v $(shell pwd)/target/release/spin:/from-host/target/release/spin
endif

ifneq (,$(wildcard $(shell pwd)/target/debug/spin))
	E2E_SPIN_DEBUG_VOLUME_MOUNT = -v $(shell pwd)/target/debug/spin:/from-host/target/debug/spin
endif

## Reset volume mounts for e2e-tests if Darwin because the
## spin binaries built on macOS won't run in the docker container
ifeq ($(shell uname -s),Darwin)
	E2E_SPIN_RELEASE_VOLUME_MOUNT = 
	E2E_SPIN_DEBUG_VOLUME_MOUNT =
	E2E_BUILD_SPIN = true
endif

## overrides for Windows
ifeq ($(OS),Windows_NT)
	LOG_LEVEL_VAR = 
endif

.PHONY: build
build:
	cargo build --release

.PHONY: install
install:
	cargo install --path . --locked

.PHONY: test
test: lint test-unit test-integration

.PHONY: lint
lint:
	cargo clippy --all --all-targets --features all-tests -- -D warnings
	cargo fmt --all -- --check

.PHONY: lint-rust-examples
lint-rust-examples:
	for manifest_path in $$(find examples  -name Cargo.toml); do \
		echo "Linting $${manifest_path}" \
		&& cargo clippy --manifest-path "$${manifest_path}" -- -D warnings \
		&& cargo fmt --manifest-path "$${manifest_path}" -- --check \
		&& (git diff --name-status --exit-code . || (echo "Git working tree dirtied by lints. Run 'make update-cargo-locks' and check in changes" && false)) \
		|| exit 1 ; \
	done

.PHONY: lint-all
lint-all: lint lint-rust-examples

## Bring all of the checked in `Cargo.lock` files up-to-date
.PHONY: update-cargo-locks
update-cargo-locks: 
	echo "Updating Cargo.toml"
	cargo update -w --offline; \
	for manifest_path in $$(find examples -name Cargo.toml); do \
		echo "Updating $${manifest_path}" && \
		cargo update --manifest-path "$${manifest_path}" -w --offline; \
	done

.PHONY: test-unit
test-unit:
	$(LOG_LEVEL_VAR) cargo test --all --no-fail-fast -- --skip integration_tests --skip spinup_tests --skip cloud_tests --nocapture

.PHONY: test-crate
test-crate:
	$(LOG_LEVEL_VAR) cargo test -p $(crate) --no-fail-fast -- --skip integration_tests --skip spinup_tests --skip cloud_tests --nocapture

.PHONY: test-integration
test-integration:
	cargo test -F e2e-tests -- runtime_tests --nocapture; \
	$(LOG_LEVEL_VAR) cargo test --test integration --no-fail-fast -- --skip spinup_tests --skip cloud_tests --nocapture

.PHONY: test-spin-up
test-spin-up: build-test-spin-up run-test-spin-up

.PHONY: build-test-spin-up
build-test-spin-up:
	docker build -t spin-e2e-tests --build-arg FETCH_SPIN=$(E2E_FETCH_SPIN) --build-arg BUILD_SPIN=$(E2E_BUILD_SPIN) -f $(E2E_TESTS_DOCKERFILE) .

.PHONY: run-test-spin-up
run-test-spin-up:
	REDIS_IMAGE=$(REDIS_IMAGE) MYSQL_IMAGE=$(MYSQL_IMAGE) POSTGRES_IMAGE=$(POSTGRES_IMAGE) \
	BUILD_SPIN=$(E2E_BUILD_SPIN) \
	docker compose -f e2e-tests-docker-compose.yml run $(E2E_SPIN_RELEASE_VOLUME_MOUNT) $(E2E_SPIN_DEBUG_VOLUME_MOUNT) e2e-tests

.PHONY: test-sdk-go
test-sdk-go:
	$(MAKE) -C sdk/go test

# simple convenience for developing with TLS
.PHONY: tls
tls: ${CERT_NAME}.crt.pem

$(CERT_NAME).crt.pem:
	openssl req -newkey rsa:2048 -nodes -keyout $(CERT_NAME).key.pem -x509 -days 365 -out $(CERT_NAME).crt.pem
