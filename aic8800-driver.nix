# Bridge for /etc/nixos: loads the aic8800.nix module from this repository.
let
  src = builtins.fetchGit {
    url = "https://github.com/codebyallan/aic8800-nixos";
    rev = "1947175c80757f1911f6f35a67732f6147a6f8e2";
  };
in
import "${src}/aic8800.nix"
