NVIM ?= nvim

.PHONY: test fmt fmt-check

test:
	$(NVIM) --clean -l tests/run.lua

fmt:
	stylua lua plugin tests

fmt-check:
	stylua --check lua plugin tests
