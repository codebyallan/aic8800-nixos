# Bridge for /etc/nixos: loads the aic8800.nix module from this repository.
let
  src = builtins.fetchGit {
    url = "https://github.com/codebyallan/aic8800-nixos";
  };
in
import "${src}/aic8800.nix"
