# aic8800-nixos

NixOS module for the AIC8800D80 USB Wi-Fi 6 adapter (`chip_mcu_id=0`).

The driver comes from the fork [codebyallan/aic8800d80](https://github.com/codebyallan/aic8800d80), at the commit pinned in `aic8800.nix`.

## Repository contents

| File | Purpose |
| --- | --- |
| `aic8800.nix` | Main module: builds the kernel module and firmware and enables the driver. |
| `aic8800-driver.nix` | Bridge file for `/etc/nixos`. It downloads this repository and loads `aic8800.nix` from it. |

## Installation

1. Copy the bridge file to `/etc/nixos/`:

       sudo cp aic8800-driver.nix /etc/nixos/

2. In `/etc/nixos/configuration.nix`, add `./aic8800-driver.nix` to `imports` and enable the driver:

       imports = [ ./aic8800-driver.nix ];
       hardware.aic8800d80.enable = true;

3. Apply the configuration. Secure Boot must be disabled, because the kernel module is not signed:

       sudo nixos-rebuild switch
       sudo reboot

## Updating the driver

1. Change `rev` in `aic8800.nix` to the new commit of the fork.
2. Commit and push this repository.
3. Run `sudo nixos-rebuild switch`.

## Notes

- **Secure Boot:** the module is not signed, so it does not load while Secure Boot is enabled.
- **Firmware path:** the firmware is installed to `/run/current-system/firmware`, and the driver is configured to read from there.
- **CD-ROM mode:** the adapter first appears as a USB storage device. A udev rule ejects it so it switches to Wi-Fi mode.
- **Unpinned bridge:** `aic8800-driver.nix` fetches this repository without a `rev`, so it always uses the latest commit of the default branch. Only the driver version is pinned, in `aic8800.nix`.