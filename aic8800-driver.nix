# Bridge for /etc/nixos: loads the aic8800.nix module from this repository.
let
  src = builtins.fetchGit {
    url = "https://github.com/codebyallan/aic8800-nixos";
    rev = "97a11d0e4bada9600b2d103b2449fcdf66d653d7";
  };
in
import "${src}/aic8800.nix"
