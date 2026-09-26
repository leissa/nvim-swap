NVIM ?= nvim

# One spec instead of the whole suite: `make test SPEC=ts`, `SPEC='ts keys'`.
SPEC ?=

.PHONY: test fmt fmt-check doc clean

## Run the whole suite, or a single file with `make test SPEC=ts`. Specs that
## need a tree-sitter parser skip when it is missing, so check the `skipped`
## count before trusting a green run.
test:
	$(NVIM) --clean -l tests/run.lua $(SPEC)

## Reformat the tree.
fmt:
	stylua lua plugin tests

## What CI enforces.
fmt-check:
	stylua --check lua plugin tests

## Regenerate doc/tags.
doc:
	$(NVIM) --headless --clean -c 'helptags doc' -c q

clean:
	rm -f doc/tags
