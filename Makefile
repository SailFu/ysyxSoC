V_FILE_GEN   = build/ysyxSoCTop.sv
V_FILE_FINAL = build/ysyxSoCFull.v
SCALA_FILES = $(shell find src/ -name "*.scala")

# Java is required by mill. Some environments (e.g. non-interactive shells)
# may not have JAVA_HOME/PATH initialized, so we try a common local JDK path.
JAVA_BIN := $(shell command -v java 2>/dev/null)
ifeq ($(JAVA_BIN),)
  JAVA_BIN := $(shell ls -1 $(HOME)/java/*/bin/java 2>/dev/null | head -n 1)
endif
ifeq ($(JAVA_BIN),)
  $(error java not found in PATH and no $(HOME)/java/*/bin/java. Please install JDK 17+ or export JAVA_HOME/bin into PATH)
endif
JAVA_BIN_DIR := $(dir $(JAVA_BIN))
export PATH := $(JAVA_BIN_DIR):$(PATH)

# Firtool version
FIRTOOL_VERSION = 1.105.0
FIRTOOL_PATCH_DIR = $(shell pwd)/patch/firtool

$(V_FILE_FINAL): $(SCALA_FILES)
# Replace firtool with a newer version
# TODO: This can be removed after chisel publishes a new version
	@./patch/update-firtool.sh $(FIRTOOL_VERSION) $(FIRTOOL_PATCH_DIR)
	CHISEL_FIRTOOL_PATH=$(FIRTOOL_PATCH_DIR)/firtool-$(FIRTOOL_VERSION)/bin \
	mill -i ysyxsoc.runMain ysyx.Elaborate --target-dir $(@D)
	mv $(V_FILE_GEN) $@
	sed -i -e 's/_\(aw\|ar\|w\|r\|b\)_\(\|bits_\)/_\1/g' $@
	sed -i '/firrtl_black_box_resource_files.f/, $$d' $@

verilog: $(V_FILE_FINAL)

clean:
	-rm -rf build/

dev-init:
	git submodule update --init --recursive
	cd rocket-chip && git apply ../patch/rocket-chip.patch

.PHONY: verilog clean dev-init
