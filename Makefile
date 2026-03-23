TERRA ?= terra
OUT ?=
SNAPSHOT ?= generated/terraui-runtime.asdl

.PHONY: help test asdl snapshot check demo demo-smoke

help:
	@echo "Targets:"
	@echo "  make test                 - run the current test suite"
	@echo "  make asdl                 - print emitted TerraUI ASDL"
	@echo "  make asdl OUT=path        - write emitted TerraUI ASDL to OUT"
	@echo "  make snapshot             - refresh the checked-in ASDL snapshot"
	@echo "  make check FILE=path      - compare emitted TerraUI ASDL with FILE"
	@echo "  make check                - compare emitted TerraUI ASDL with the default snapshot"
	@echo "  make demo                 - build the AOT SDL+OpenGL demo executable"
	@echo "  make demo-smoke           - build and smoke-run the demo hidden for 2 frames"

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

demo:
	@mkdir -p examples
	$(TERRA) examples/build_sdl_gl_demo.t examples/sdl_gl_demo

demo-smoke:
	./tests/aot_demo_smoke.sh
