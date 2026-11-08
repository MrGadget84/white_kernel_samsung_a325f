#!/usr/bin/env bash
# Prepare a disposable OpenHarmony HDF 6.1 LTS source overlay for this kernel.
# This script is intended for CI workspaces; it does not vendor or commit HDF.
set -euo pipefail

KERNEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HDF_ROOT="${1:?usage: prepare-hdf-overlay.sh /path/to/drivers_hdf_core}"
BOUNDS_ROOT="${2:?usage: prepare-hdf-overlay.sh /path/to/bounds_checking_function}"
# Symlink targets must be absolute: relative arguments resolve from drivers/hdf,
# not from the repository root where this script is invoked.
HDF_ROOT="$(cd "$HDF_ROOT" && pwd)"
BOUNDS_ROOT="$(cd "$BOUNDS_ROOT" && pwd)"

[[ -f "$HDF_ROOT/adapter/khdf/linux/Kconfig" ]]
[[ -f "$HDF_ROOT/adapter/khdf/linux/Makefile" ]]
[[ -d "$HDF_ROOT/framework/include" ]]
[[ -d "$HDF_ROOT/interfaces/inner_api" ]]
[[ -d "$BOUNDS_ROOT/include" ]]

cd "$KERNEL_ROOT"
mkdir -p drivers/hdf include
link_dir() {
    local source="$1" target="$2"
    if [[ -e "$target" || -L "$target" ]]; then
        echo "Refusing to overwrite existing path: $target" >&2
        exit 1
    fi
    ln -s "$source" "$target"
}

# Keep the layout expected by the upstream KHDF Makefiles.
link_dir "$HDF_ROOT/adapter/khdf/linux" drivers/hdf/khdf
link_dir "$HDF_ROOT/framework" drivers/hdf/framework
link_dir "$HDF_ROOT/interfaces/inner_api" drivers/hdf/inner_api
link_dir "$HDF_ROOT/framework/include" include/hdf
link_dir "$BOUNDS_ROOT" bounds_checking_function

# The upstream KHDF manager Makefile lists secure-C objects with absolute
# source-tree paths. Linux 4.14 Kbuild prepends $(obj) to those paths, producing
# invalid targets. Stage the same upstream sources locally in manager/src.
MANAGER_DIR="$HDF_ROOT/adapter/khdf/linux/manager"
SECUREC_SOURCES=(
    memcpy_s.c memmove_s.c memset_s.c securecutil.c secureinput_a.c
    secureprintoutput_a.c snprintf_s.c sprintf_s.c strcat_s.c strcpy_s.c
    strncat_s.c strncpy_s.c strtok_s.c vsnprintf_s.c vsprintf_s.c
)
for source in "${SECUREC_SOURCES[@]}"; do
    cp "$BOUNDS_ROOT/src/$source" "$MANAGER_DIR/src/securec_$source"
done
python3 - "$MANAGER_DIR/Makefile" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "SEC_FUNCTION_OBJECTS := $(addprefix $(OHOS_SOURCE_ROOT)/third_party/bounds_checking_function/src/,${SEC_FUNCTION_OBJECTS})"
new = "SEC_FUNCTION_OBJECTS := $(addprefix ./src/securec_,${SEC_LIB_SOURCES:.c=.o})"
if old not in s:
    raise SystemExit("Could not locate upstream SEC_FUNCTION_OBJECTS absolute-path assignment")
p.write_text(s.replace(old, new, 1))
PY

# Wrapper added by the upstream Linux 4.19 integration patch.
cat > drivers/hdf/Makefile <<'EOF'
# OpenHarmony HDF adapter wrapper.
obj-$(CONFIG_DRIVERS_HDF) += khdf/
EOF

# Linux 4.14 Samsung tree has different Kconfig/Makefile ordering from 4.19.
grep -q 'source "drivers/hdf/khdf/Kconfig"' drivers/Kconfig || \
    sed -i '/source "drivers\/switch\/Kconfig"/a source "drivers/hdf/khdf/Kconfig"' drivers/Kconfig
grep -q 'obj-$(CONFIG_DRIVERS_HDF).*hdf/' drivers/Makefile || \
    sed -i '/obj-$(CONFIG_SWITCH).*switch\//a obj-$(CONFIG_DRIVERS_HDF) += hdf/' drivers/Makefile

# The arm64 linker script already contains INIT_RAM_FS in .init.data.
if ! grep -q '_hdf_drivers_start' arch/arm64/kernel/vmlinux.lds.S; then
    python3 - <<'PY'
from pathlib import Path
p = Path("arch/arm64/kernel/vmlinux.lds.S")
s = p.read_text()
old = """\t\tINIT_RAM_FS
\t\t*(.init.rodata.* .init.bss)\t/* from the EFI stub */
\t}
\t.exit.data : {"""
if s.count(old) != 1:
    raise SystemExit("Could not uniquely locate the end of .init.data")
new = """\t\tINIT_RAM_FS
\t\t*(.init.rodata.* .init.bss)\t/* from the EFI stub */
\t}
#ifdef CONFIG_DRIVERS_HDF
\t.init.hdf_table : {
\t\t_hdf_drivers_start = .;
\t\t*(.hdf.driver)
\t\t_hdf_drivers_end = .;
\t}
#endif
\t.exit.data : {"""
s = s.replace(old, new, 1)
p.write_text(s)
PY
fi

# The upstream KHDF manager Makefile lists secure-C objects with absolute
# paths. Linux 4.14 Kbuild treats those as targets below manager/ and fails.
# Expose the required sources locally and use manager-relative object names.
MANAGER_DIR="drivers/hdf/khdf/manager"
mkdir -p "$MANAGER_DIR/src"
python3 - "$MANAGER_DIR/Makefile" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "SEC_FUNCTION_OBJECTS := $(addprefix $(OHOS_SOURCE_ROOT)/third_party/bounds_checking_function/src/,${SEC_FUNCTION_OBJECTS})"
new = "SEC_FUNCTION_OBJECTS := $(patsubst %.c,./src/%.o,$(SEC_LIB_SOURCES))"
if old not in s:
    raise SystemExit("Could not patch KHDF secure-C object paths")
p.write_text(s.replace(old, new, 1))
PY
for source in "$BOUNDS_ROOT"/src/*.c; do
    name="$(basename "$source")"
    ln -s "$source" "$MANAGER_DIR/src/$name"
done

echo "HDF overlay prepared:"
printf '  KHDF: %s\n' "$(readlink drivers/hdf/khdf)"
printf '  framework: %s\n' "$(readlink drivers/hdf/framework)"
printf '  inner_api: %s\n' "$(readlink drivers/hdf/inner_api)"
printf '  HDF headers: %s\n' "$(readlink include/hdf)"
printf '  bounds_checking_function: %s\n' "$(readlink bounds_checking_function)"
