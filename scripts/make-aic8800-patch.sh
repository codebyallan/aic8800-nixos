#!/usr/bin/env bash
# Generate the in-tree AIC8800 patch for a given kernel source tarball.
# Usage: make-aic8800-patch.sh <linux-X.Y.Z.tar.xz> <fork-commit> <out.patch>
set -euo pipefail

KSRC=$1
REV=$2
OUT=$(realpath -m -- "$3")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1. Driver source at the pinned fork commit
git clone -q https://github.com/codebyallan/aic8800d80 "$WORK/fork"
git -C "$WORK/fork" checkout -q "$REV"

# 2. Pristine kernel parents (a/)
mkdir -p "$WORK/a"
tar -xf "$KSRC" -C "$WORK/a" --strip-components=1 \
  --wildcards '*/drivers/net/wireless/Makefile' '*/drivers/net/wireless/Kconfig'
test -f "$WORK/a/drivers/net/wireless/Makefile" || { echo "parents not found in tarball"; exit 1; }

# 3. Modified tree (b/)
cp -r "$WORK/a" "$WORK/b"
W="$WORK/b/drivers/net/wireless"
S="$WORK/fork/drivers/aic8800"
D="$W/aic8800"
mkdir -p "$D/aic_load_fw" "$D/aic8800_fdrv"

cp "$S/Kconfig" "$D/Kconfig"
cp "$S/aicwf_firmware.h" "$D/"
for sub in aic_load_fw aic8800_fdrv; do
  cp "$S/$sub/Kconfig" "$D/$sub/Kconfig"
  (cd "$S/$sub" && find . -type f ! -name Makefile ! -name Kconfig ! -name .gitignore \
     -exec cp --parents {} "$D/$sub/" \;)
done

# Makefiles written for in-tree build (flags resolved from fork commit 341ac7e)
cat > "$D/Makefile" <<'MK'
# SPDX-License-Identifier: GPL-2.0
obj-$(CONFIG_AIC_LOADFW_SUPPORT) += aic_load_fw/
obj-$(CONFIG_AIC8800_WLAN_SUPPORT) += aic8800_fdrv/
MK

cat > "$D/aic_load_fw/Makefile" <<'MK'
# SPDX-License-Identifier: GPL-2.0
ccflags-y += -DAICWF_USB_SUPPORT -DCONFIG_RFTEST -DCONFIG_USB_BT \
	-DCONFIG_USB_MSG_EP -DCONFIG_LINK_DET_5G -DCONFIG_PREALLOC_TXQ \
	-DCONFIG_PLATFORM_UBUNTU

obj-$(CONFIG_AIC_LOADFW_SUPPORT) += aic_load_fw.o
aic_load_fw-y := aic_bluetooth_main.o aicbluetooth.o aicwf_usb.o \
	aic_txrxif.o aicbluetooth_cmds.o aic_compat_8800d80.o \
	aic_compat_8800d80x2.o md5.o aicwf_txq_prealloc.o
MK

cat > "$D/aic8800_fdrv/Makefile" <<'MK'
# SPDX-License-Identifier: GPL-2.0
ccflags-y += -Wno-implicit-fallthrough
ccflags-y += -DCONFIG_RWNX_P2P_DEBUGFS
ccflags-y += -DNX_VIRT_DEV_MAX=4 -DNX_REMOTE_STA_MAX_FOR_OLD_IC=8 \
	-DNX_REMOTE_STA_MAX=32 -DNX_MU_GROUP_MAX=62 -DNX_TXDESC_CNT=64 \
	-DNX_TX_MAX_RATES=4 -DNX_CHAN_CTXT_CNT=3 -DNX_TXQ_CNT=5
ccflags-y += -DCONFIG_START_FROM_BOOTROM -DCONFIG_VRF_DCDC_MODE \
	-DCONFIG_ROM_PATCH_EN -DCONFIG_COEX -DCONFIG_RWNX_FULLMAC \
	-DCONFIG_RWNX_RADAR -DCONFIG_RWNX_MON_XMIT -DCONFIG_RWNX_DBG \
	-DCONFIG_RFTEST -DCONFIG_MCC -DAICWF_USB_SUPPORT -DCONFIG_USER_MAX=1 \
	-DAICWF_RX_REORDER -DAICWF_ARP_OFFLOAD -DUSE_5G -DCONFIG_USB_BT \
	-DCONFIG_ALIGN_8BYTES -DCONFIG_TXRX_THREAD_PRIO -DCONFIG_USB_ALIGN_DATA \
	-DCONFIG_MAC_RANDOM_IF_NO_MAC_IN_EFUSE \
	'-DDEFAULT_COUNTRY_CODE="00"' \
	-DCONFIG_RX_NETIF_RECV_SKB -DCONFIG_USB_MSG_OUT_EP -DCONFIG_USB_MSG_IN_EP \
	-DCONFIG_USE_USB_ZERO_PACKET -DCONFIG_STA_SCAN_WHEN_P2P_WORKING \
	-DCONFIG_SUPPORT_REALTIME_CHANGE_MAC -DCONFIG_PREALLOC_TXQ \
	-DCONFIG_DPD -DCONFIG_FORCE_DPD_CALIB -DCONFIG_FILTER_TCP_ACK
ccflags-y += -I$(src)

obj-$(CONFIG_AIC8800_WLAN_SUPPORT) += aic8800_fdrv.o
aic8800_fdrv-y := rwnx_wakelock.o rwnx_msg_tx.o rwnx_msg_rx.o rwnx_utils.o \
	rwnx_cmds.o rwnx_irqs.o rwnx_cfgfile.o rwnx_strs.o rwnx_rx.o rwnx_tx.o \
	rwnx_txq.o rwnx_main.o rwnx_mod_params.o rwnx_mesh.o rwnx_platform.o \
	rwnx_pci.o rwnx_dini.o rwnx_v7.o ipc_host.o rwnx_tdls.o regdb.o md5.o \
	aic_vendor.o aic_priv_cmd.o aicwf_compat_8800dc.o aicwf_compat_8800d80.o \
	aicwf_compat_8800d80x2.o aicwf_compat_8800d80n.o aicwf_compat_8800dln.o \
	rwnx_radar.o aicwf_tcp_ack.o usb_host.o aicwf_txrxif.o aicwf_usb.o
MK

# 4. Hook the driver into the parent Makefile and Kconfig.
#    Fails loudly if the anchor lines changed in this kernel version.
python3 - "$W" <<'PY'
import sys, pathlib
w = pathlib.Path(sys.argv[1])
def edit(path, old, new):
    s = path.read_text()
    if s.count(old) != 1:
        sys.exit(f"anchor not found exactly once in {path}: {old!r}")
    path.write_text(s.replace(old, new, 1))
edit(w / "Makefile", "obj-$(CONFIG_WLAN) += virtual/",
     "obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800/\n\nobj-$(CONFIG_WLAN) += virtual/")
edit(w / "Kconfig", 'source "drivers/net/wireless/virtual/Kconfig"',
     'source "drivers/net/wireless/aic8800/Kconfig"\n\nsource "drivers/net/wireless/virtual/Kconfig"')
PY

# 5. Diff and verify it applies to a clean copy of the parents
cd "$WORK"
diff -ruN a b > out.patch || true
rm -rf check && cp -r a check
(cd check && patch -p1 --dry-run -s < "$WORK/out.patch")
cp out.patch "$OUT"
echo "wrote $OUT ($(grep -c '^+++ ' "$OUT") files, dry-run OK)"