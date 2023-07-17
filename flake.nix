{
  description = "Utility to automate downloads of torrent series";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, opam-nix }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = (import nixpkgs) { inherit system; };

        on = opam-nix.lib.${system};
        localPackagesQuery = builtins.mapAttrs (_: pkgs.lib.last)
          (on.listRepo (on.makeOpamRepo ./.));

        devPackagesQuery = {
          # You can add "development" packages here. They will get added to the devShell automatically.
          ocaml-lsp-server = "*";
          ocamlformat = "*";
          utop = "*";
        };

        query = devPackagesQuery // {
          ## You can force versions of certain packages here, e.g:
          # - force the ocaml compiler to be taken from opam-repository:
          ocaml-base-compiler = "4.14.1";
          # - or force the compiler to be taken from nixpkgs and be a certain version:
          # ocaml-system = "4.14.1";
          ## - or force ocamlfind to be a certain version:
          # ocamlfind = "1.9.2";
        };

        scope = on.buildOpamProject' { } ./. query;
        overlay = final: prev: {
          # You can add overrides here
        };
        scope' = scope.overrideScope' overlay;

        devPackages = builtins.attrValues
          (pkgs.lib.getAttrs (builtins.attrNames devPackagesQuery) scope');
        # Packages in this workspace
        packages =
          pkgs.lib.getAttrs (builtins.attrNames localPackagesQuery) scope';
      in
      {
        legacyPackages = scope';

        inherit packages;

        devShells.default = pkgs.mkShell {
          inputsFrom = builtins.attrValues packages;
          buildInputs = devPackages ++ [
            # You can add packages from nixpkgs here
          ];
        };
      });
}
