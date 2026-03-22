TERRA ?= terra
OUT ?=
SNAPSHOT ?= generated/terraui-runtime.asdl

.PHONY: help test asdl snapshot check

help:
	@echo "Targets:"
	@echo "  make test                 - run the current test suite"
	@echo "  make asdl                 - print emitted TerraUI ASDL"
	@echo "  make asdl OUT=path        - write emitted TerraUI ASDL to OUT"
	@echo "  make snapshot             - refresh the checked-in ASDL snapshot"
	@echo "  make check FILE=path      - compare emitted TerraUI ASDL with FILE"
	@echo "  make check                - compare emitted TerraUI ASDL with the default snapshot"

test:
	./tools/run_tests.sh

asdl:
	@if [ -n "$(OUT)" ]; then \
		$(TERRA) tools/emit_terraui_asdl.t $(OUT); \
	else \
		$(TERRA) tools/emit_terraui_asdl.t; \
	fi

snapshot:
	@mkdir -p "$(dir $(SNAPSHOT))"
	$(TERRA) tools/emit_terraui_asdl.t $(SNAPSHOT)

check:
	$(TERRA) tools/emit_terraui_asdl.t --check $(if $(FILE),$(FILE),$(SNAPSHOT))
