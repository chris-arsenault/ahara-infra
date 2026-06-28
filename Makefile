.PHONY: ci shared-crates-ci shared-crates-lint shared-crates-fmt shared-crates-test lint fmt test test-integration terraform-fmt-check build deploy

ci: shared-crates-ci lint fmt test terraform-fmt-check

shared-crates-ci: shared-crates-lint shared-crates-fmt shared-crates-test

shared-crates-lint:
	cargo clippy --workspace -- -D warnings

shared-crates-fmt:
	cargo fmt --check

shared-crates-test:
	cargo test --workspace

lint:
	cd backend && cargo clippy -- -D warnings

fmt:
	cd backend && cargo fmt --check

test:
	cd backend && cargo test --lib

test-integration:
	cd backend && cargo test --test '*'

terraform-fmt-check:
	terraform fmt -check -recursive infrastructure/terraform/

build:
	cd backend && cargo lambda build --release

deploy:
	scripts/deploy.sh
