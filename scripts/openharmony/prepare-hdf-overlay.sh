#!/usr/bin/env bash
# Prepare a disposable OpenHarmony HDF 6.1 LTS source overlay for this kernel.
# This script is intended for CI workspaces; it does not vendor or commit HDF.
set -euo pipefail

KERNEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HDF_ROOT="${1:?usage: prepare-hdf-overlay.sh /path/to/drivers_hdf_core}"
BOUNDS_ROOT="${2:?usage: prepare-hdf-overlay.sh /path/to/bounds_checking_function}"

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
needle = "\t\tINIT_RAM_FS"
if s.count(needle) != 1:
    raise SystemExit("Could not uniquely locate INIT_RAM_FS in arm64 linker script")
insert = """\t\tINIT_RAM_FS
#ifdef CONFIG_DRIVERS_HDF
\t}
\t.init.hdf_table : {
\t\t_hdf_drivers_start = .;
\t\t*(.hdf.driver)
\t\t_hdf_drivers_end = .;
#endif
"""
# Preserve the existing remainder of the .init.data section.
s = s.replace(needle, insert.rstrip("\n"), 1)
p.write_text(s)
PY
fi

echo "HDF overlay prepared:"
printf '  KHDF: %s\n' "$(readlink drivers/hdf/khdf)"
printf '  framework: %s\n' "$(readlink drivers/hdf/framework)"
printf '  inner_api: %s\n' "$(readlink drivers/hdf/inner_api)"
printf '  HDF headers: %s\n' "$(readlink include/hdf)"
printf '  bounds_checking_function: %s\n' "$(readlink bounds_checking_function)"
