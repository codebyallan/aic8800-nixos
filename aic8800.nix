# NixOS module for the AIC8800D80 USB Wi-Fi 6 adapter (chip_mcu_id=0).
# Driver: fork codebyallan/aic8800d80, branch main, pinned commit below.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.aic8800d80;

  # Driver source at the commit known to work on Fedora
  # (srcversion BE2A4B7DFC12438B57818AC).
  # builtins.fetchGit with an explicit rev does not need a hash.
  aic8800-src = builtins.fetchGit {
    url = "https://github.com/codebyallan/aic8800d80";
    rev = "341ac7e7cda493a3204bda9c3671168bf831a3f1";
  };

  aic8800-firmware = pkgs.stdenvNoCC.mkDerivation {
    pname = "aic8800-firmware";
    version = "1.0.0";
    dontUnpack = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/firmware
      cp -r --no-preserve=mode ${aic8800-src}/fw/. $out/lib/firmware/
      runHook postInstall
    '';
    # The driver opens the firmware files directly, so they must not be
    # compressed (zstd).
    passthru.compressFirmware = false;
  };

  aic8800-kmodule = config.boot.kernelPackages.callPackage ({ stdenv, kmod, kernel, kernelModuleMakeFlags }:
    stdenv.mkDerivation {
      pname = "aic8800";
      version = "1.0.0";
      dontUnpack = true;
      hardeningDisable = [ "all" ];
      nativeBuildInputs = [ kmod ] ++ kernel.moduleBuildDependencies;
      enableParallelBuilding = true;
      makeFlags = kernelModuleMakeFlags ++ [
        "KVER=${kernel.modDirVersion}"
        "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      ];
      # Copy the source into a writable directory and apply the NixOS-specific
      # adjustments.
      preBuild = ''
        cp -r --no-preserve=mode ${aic8800-src}/drivers/aic8800 ./src
        cd src
        # Point the firmware loader to the NixOS firmware path instead of /lib/firmware.
        substituteInPlace aic_load_fw/aicbluetooth.c \
          --replace-fail '"/lib/firmware"' '"/run/current-system/firmware"'
        # Add an install target that Nix can call to install the module.
        printf 'aic_install:\n\tmake -C $(KDIR) M=$(PWD) modules_install INSTALL_MOD_PATH=$(INSTALL_MOD_PATH)\n' >> Makefile
      '';
      installTargets = [ "aic_install" ];
      installFlags = [ "INSTALL_MOD_PATH=${placeholder "out"}" ];
      postInstall = ''
        # Remove the generated module index files; depmod regenerates them.
        rm -f $out/lib/modules/${kernel.modDirVersion}/modules.*
      '';
    }) { };
in
{
  options.hardware.aic8800d80.enable = lib.mkEnableOption "AIC8800D80 USB Wi-Fi 6 adapter driver";

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [ aic8800-kmodule ];
    boot.kernelModules = [ "aic_load_fw" "aic8800_fdrv" ];
    hardware.firmware = [ aic8800-firmware ];
    boot.extraModprobeConfig = ''
      options aic_load_fw aic_fw_path=/run/current-system/firmware/aic8800D80
    '';

    # Pandora 88M80 mode-switch config. The file name contains a colon,
    # which usb_modeswitch expects.
    environment.etc."usb_modeswitch.d/1111:1111".source =
      "${aic8800-src}/usb_modeswitch/1111_1111";

    services.udev.extraRules = ''
      # AIC8800 dongles enumerate first as a write-protected "driver CD"
      # USB mass storage device. Ejecting that LUN makes the chip
      # re-enumerate in WLAN mode (a69c:8d80 "AIC Wlan").
      KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5721", RUN+="${pkgs.eject}/bin/eject /dev/%k"

      # Pandora 88M80 (1111:1111): send the F3 then F2 CDBs to switch to
      # a69c:8d80. Matched on product "88M80*" because 1111:1111 is also
      # used by unrelated flash drives.
      ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="1111", ATTR{idProduct}=="1111", ATTR{product}=="88M80*", RUN+="${pkgs.usb-modeswitch}/bin/usb_modeswitch -b $attr{busnum} -g $attr{devnum} -c /etc/usb_modeswitch.d/1111:1111"
    '';
  };
}