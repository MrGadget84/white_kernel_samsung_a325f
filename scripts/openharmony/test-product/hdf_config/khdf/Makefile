# Minimal A32 product HCS build recipe for KHDF integration testing.
# Mirrors the upstream OpenHarmony product hdf_config/khdf Makefile flow.

ifeq ($(LOCAL_HCS_ROOT),)
  LOCAL_HCS_ROOT := $(PRODUCT_PATH)
endif
CURRENT_DIR := $(abspath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
SOURCE_ROOT := $(abspath $(CURRENT_DIR)/../../../../../)

HC_GEN_DIR := $(abspath $(SOURCE_ROOT)/drivers/hdf_core/framework/tools/hc-gen)
ifneq ($(OUT_DIR),)
HC_GEN := $(OUT_DIR)/kernel/OBJ/${KERNEL_VERSION}/drivers/hdf/khdf/hc_gen_build/hc-gen
else
HC_GEN := $(HC_GEN_DIR)/build/hc-gen
endif
LOCAL_HCS_ROOT := $(CURRENT_DIR)
HCS_DIR := $(LOCAL_HCS_ROOT)
HCB_FLAGS := -b -i -a

HCS_OBJ := hdf_hcs_hex.o
HCS_OBJ_SRC := $(subst .o,.c,$(notdir $(HCS_OBJ)))
CONFIG_GEN_HEX_SRC := $(addprefix $(LOCAL_HCS_ROOT)/, $(HCS_OBJ_SRC))
CONFIG_HCS_SRC := $(subst _hcs_hex.o,.hcs,$(addprefix $(HCS_DIR)/, $(HCS_OBJ)))

$(obj)/$(HCS_OBJ): $(CONFIG_GEN_HEX_SRC)
	$(Q)$(CC) $(c_flags) -c -o $@ $<
	$(Q)rm -f $<

$(CONFIG_GEN_HEX_SRC): $(LOCAL_HCS_ROOT)/%_hcs_hex.c: $(HCS_DIR)/%.hcs | $(HC_GEN)
	$(Q)echo gen A32 HDF built-in config
	$(Q)if [ ! -d $(dir $@) ]; then mkdir -p $(dir $@); fi
	$(Q)$(HC_GEN) $(HCB_FLAGS) -o $(subst _hex.c,,$(@)) $<

$(HC_GEN):
	$(HIDE)make -C $(HC_GEN_DIR) BUILD_DIR=$(dir $@)

obj-$(CONFIG_DRIVERS_HDF) += $(HCS_OBJ)
