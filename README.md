# AIC8800D80 USB Wi-Fi 6 on NixOS

NixOS module for the AIC8800D80 USB Wi-Fi 6 adapter, using the driver from
[codebyallan/aic8800d80](https://github.com/codebyallan/aic8800d80).

It covers the whole chain: mode-switching the dongle from its storage ("CD")
mode into Wi-Fi mode, installing the firmware, and loading the driver either
inside the kernel or as an external module.

## Supported hardware

| USB ID (before) | USB ID (after switch) | Product string | Notes |
|---|---|---|---|
| `1111:1111` | `a69c:8d80` / `a69c:8d81` | `88M80` → `AIC 8800D80` | Mode switch via `usb_modeswitch` |
| `a69c:5721` | `a69c:8d80` | driver CD | Mode switch via `eject` |

The `1111:1111` case is handled by `usb_modeswitch/1111_1111` in the driver
repository. Confirm your device with `lsusb` and `dmesg`: it must show
`idVendor=1111, idProduct=1111` and product `88M80` before the switch.

## Modes

The module supports two ways of loading the driver. Pick one.

| Mode | Driver location | Secure Boot (lockdown) | Kernel patch |
|---|---|---|---|
| `in-tree` (default) | Built into the kernel, signed by the kernel build key | Compatible | Required |
| `external` | Out-of-tree `.ko`, built against the running kernel | **Not compatible**: unsigned, rejected under `lockdown=integrity` | Must not be present |

Only one mode may be active. Mixing them loads an unpredictable copy of the module.

## Repository layout

```
aic8800.nix                    NixOS module (options, firmware, udev, drivers)
aic8800-driver.nix             bridge loaded from /etc/nixos; fetches aic8800.nix at a pinned rev
scripts/make-aic8800-patch.sh  generates the in-tree kernel patch
```

## Requirements

- NixOS 26.05 (`nixos-rebuild` without flakes works).
- Network access to GitHub during the build (the driver is fetched with `builtins.fetchGit`).
- For patch generation: `nix`, `git`, `tar`, `python3`, `patch`, `diff`, `coreutils`.
  If they are not in your `PATH`, run the script inside `nix-shell` (see step 1).

## Quick start: `in-tree` mode (recommended)

### 1. Generate the kernel patch

The patch must match the kernel that NixOS builds. Get its source first:

```bash
export SRC=$(nix-build '<nixpkgs>' -A linuxPackages.kernel.src --no-out-link)
echo "$SRC"
uname -r   # must match the version in $SRC (e.g. 6.18.60)
```

Then run the generator from the repository root, pointing at the driver commit
the module uses. Use `nix-shell` if `python3` or the other tools are missing:

```bash
nix-shell -p python3 git gnupatch gnutar diffutils coreutils --run \
  './scripts/make-aic8800-patch.sh "$SRC" 341ac7e7cda493a3204bda9c3671168bf831a3f1 ./aic8800-in-tree.patch'
```

The script:

1. clones the driver repository and checks out the given commit;
2. extracts `drivers/net/wireless/{Makefile,Kconfig}` from the kernel tarball;
3. copies the driver into `drivers/net/wireless/aic8800/`, with in-tree
   `Makefile`s and `Kconfig`s;
4. adds the two hook lines to the parent `Makefile` and `Kconfig`;
5. writes the patch and verifies it with `patch --dry-run` on a clean copy.

On success it prints `wrote ... (138 files, dry-run OK)`. It fails with
`anchor not found` if the kernel changed the two hook lines, and it does not
write the patch if the dry run fails.

Check the result, then copy it next to `configuration.nix`:

```bash
ls -l ./aic8800-in-tree.patch
sudo cp ./aic8800-in-tree.patch /etc/nixos/
```

### 2. Configure NixOS

In `/etc/nixos/configuration.nix`, keep exactly one `boot.kernelPatches` block:

```nix
  boot.kernelPatches = [{
    name = "aic8800-in-tree";
    patch = ./aic8800-in-tree.patch;
    structuredExtraConfig = with lib.kernel; {
      MODULE_SIG = lib.mkForce yes;
      MODULE_SIG_FORMAT = lib.mkForce yes;
      MODULE_SIG_SHA512 = lib.mkForce yes;
      MODULE_SIG_ALL = lib.mkForce yes;
      SECURITY_LOCKDOWN_LSM = lib.mkForce yes;
      SECURITY_LOCKDOWN_LSM_EARLY = lib.mkForce yes;
      AIC_WLAN_SUPPORT = yes;
      AIC_LOADFW_SUPPORT = module;
      AIC8800_WLAN_SUPPORT = module;
    };
  }];

  hardware.aic8800d80.enable = true;
  hardware.aic8800d80.mode = "in-tree";

  # Bluetooth stack (bluetoothd and bluetoothctl). The adapter's Bluetooth
  # interface is handled by the kernel's btusb driver; this enables the daemon.
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
```

`lockdown` is compiled in but inactive until booted with `lockdown=integrity`.

### 3. Build, then switch

```bash
cd /etc/nixos
sudo nixos-rebuild build
```

The kernel is recompiled, which takes a long time. Only run `switch` after
`build` succeeds:

```bash
sudo nixos-rebuild switch
sudo reboot
```

### 4. Verify

```bash
readlink /run/booted-system
modinfo -F filename aic8800_fdrv      # expect .../kernel/drivers/net/wireless/aic8800/...
modinfo aic8800_fdrv | grep -i signer # expect a "signer:" line
zcat /proc/config.gz | grep -E "MODULE_SIG=|AIC8800_WLAN|AIC_LOADFW"
nmcli device status                   # wlan0 should connect
bluetoothctl list                     # controller should appear
systemctl status bluetooth --no-pager # bluetoothd should be active
```

If `modinfo -F filename` still points to `updates/`, the external module is still
being loaded. Check that `boot.extraModulePackages` is not set in the module.

### 5. Lockdown test (optional, one boot only)

This shows whether the driver survives Secure Boot-style enforcement, without
changing the boot entry permanently:

1. Reboot and open the systemd-boot menu (Space or Esc).
2. Select the current generation, press `e`.
3. At the end of the `options` line, add a space and `lockdown=integrity`.
4. Boot, then check:

```bash
cat /proc/cmdline                     # must contain lockdown=integrity
cat /sys/kernel/security/lockdown     # must show [integrity]
nmcli device status                   # wlan0 must stay connected
sudo dmesg | grep -i -E "lockdown|aic8800|signature" | tail -20
```

A reboot without the parameter restores the normal state.

## `external` mode

Use this only if you do not need lockdown.

```nix
  hardware.aic8800d80.enable = true;
  hardware.aic8800d80.mode = "external";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
```

Also **remove** the `aic8800-in-tree` entry from `boot.kernelPatches` (the whole
block, or at least the `patch` and the `AIC*` options). If the kernel still has
the driver built in, both copies get compiled.

Verify:

```bash
modinfo -F filename aic8800_fdrv   # expect .../updates/...
```

Expect `signer:` to be empty, and expect `lockdown=integrity` to make the
Wi-Fi driver fail to load.

## Patch generator: details

Usage:

```bash
./scripts/make-aic8800-patch.sh <linux-X.Y.Z.tar.xz> <driver-commit> <output.patch>
```

- The output path is resolved from the directory where you run the script.
- Run it again for every kernel version change.
- Output is deterministic for the same kernel and driver commit, apart from the
  timestamps in the diff headers.
- If it stops with `anchor not found exactly once`, the kernel moved the two
  hook lines in `drivers/net/wireless/Makefile` or `Kconfig`. Update the anchors
  in the script before retrying.
- If the dry run fails, the generated patch does not apply to the kernel.
  Do not copy it to `/etc/nixos`.
- The script does not compile the kernel. `nixos-rebuild build` is the real test.

The compiler flags and object lists in the generated `Makefile`s come from the
driver commit given to the script, and were resolved from the driver's original
Makefiles. If the driver changes its flags, update the lists in the script to match.

## Updating

### Kernel update (NixOS moves to a new kernel)

1. Try `nixos-rebuild build`. If it fails with a patch error, the kernel moved.
2. Regenerate the patch with the new kernel tarball (step 1 of Quick start).
3. Rebuild. If the build fails in compilation rather than in patch application,
   the driver code needs changes for that kernel API.
4. Verify with the checks in step 4.

Keep the previous generation available in the boot menu in case the new build
does not boot.

### Driver update

1. Push the new commit to this repository, or change `rev` in `aic8800-driver.nix`.
2. Update the commit in the patch generation command, and regenerate the patch.
3. Rebuild and verify.

## Secure Boot

This README covers the kernel side only: module signing and lockdown. Enabling
Secure Boot in firmware also needs a signed bootloader and UKIs (for example with
lanzaboote). That is not configured here yet. Do not enable Secure Boot in the
firmware until the lockdown check above passes on the current generation.