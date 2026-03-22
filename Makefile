TERRA ?= terra
OUT ?=

.PHONY: help test asdl check

help:
	@echo "Targets:"
	@echo "  make test              - run the current test suite"
	@echo "  make asdl              - print emitted TerraUI ASDL"
	@echo "  make asdl OUT=path     - write emitted TerraUI ASDL to OUT"
	@echo "  make check FILE=path   - compare emitted TerraUI ASDL with FILE"

test:
	./tools/run_tests.sh

asdl:
	@if [ -n "$(OUT)" ]; then \
		$(TERRA) tools/emit_terraui_asdl.t $(OUT); \
	else \
		$(TERRA) tools/emit_terraui_asdl.t; \
	fi

check:
	@test -n "$(FILE)" || (echo "usage: make check FILE=path" >&2; exit 1)
	$(TERRA) tools/emit_terraui_asdl.t --check $(FILE)
