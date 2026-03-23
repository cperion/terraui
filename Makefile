TERRA ?= terra
LOVE  ?= love
OUT   ?=
SNAPSHOT ?= generated/terraui-runtime.asdl

.PHONY: help test asdl snapshot check \
        demo demo-run demo-smoke \
        love2d love2d-build love2d-run

help:
	@echo "Targets:"
	@echo ""
	@echo "  Testing"
	@echo "    make test                 run the test suite"
	@echo ""
	@echo "  SDL + OpenGL demo (AOT executable)"
	@echo "    make demo                 build examples/sdl_gl_demo"
	@echo "    make demo-run             build and run"
	@echo "    make demo-smoke           build and smoke-run (hidden, 2 frames)"
	@echo ""
	@echo "  Love2D demo (compiled kernel + LuaJIT FFI)"
	@echo "    make love2d               build and run"
	@echo "    make love2d-build         build only"
	@echo "    make love2d-run           run only (must build first)"
	@echo ""
	@echo "  Schema / ASDL"
	@echo "    make asdl                 print emitted TerraUI ASDL"
	@echo "    make asdl OUT=path        write emitted ASDL to a file"
	@echo "    make snapshot             refresh the checked-in ASDL snapshot"
	@echo "    make check                compare emitted ASDL with the snapshot"
	@echo "    make check FILE=path      compare emitted ASDL with a file"

# ── Tests ────────────────────────────────────────────────────

test:
	./tools/run_tests.sh

# ── Schema / ASDL ───────────────────────────────────────────

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

# ── SDL + OpenGL demo ───────────────────────────────────────

demo:
	@mkdir -p examples
	$(TERRA) examples/build_sdl_gl_demo.t examples/sdl_gl_demo

demo-run: demo
	./examples/sdl_gl_demo

demo-smoke:
	./tests/aot_demo_smoke.sh

# ── Love2D demo ─────────────────────────────────────────────

love2d-build:
	$(TERRA) tools/build_component.t examples/love2d/ui_def.t --prefix demo_ui -o examples/love2d

love2d-run:
	$(LOVE) examples/love2d

love2d: love2d-build love2d-run
