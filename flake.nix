{
  description = "Utility to automate downloads of torrent series";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat.url = "github:edolstra/flake-compat";
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        flake-compat.follows = "flake-compat";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      opam-nix,
    }:
    let
      makeOpamPkgs =
        {
          devPackages,
          ocamlVersion,
          overlay ? (final: prev: { }),
        }:
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };

          opamNixLib = opam-nix.lib.${system};

          localPackagesQuery = builtins.mapAttrs (_: pkgs.lib.last) (
            opamNixLib.listRepo (opamNixLib.makeOpamRepo ./.)
          );

          devPackagesQuery = devPackages;

          query = devPackagesQuery // {
            ocaml-base-compiler = ocamlVersion;
          };

          scope = (opamNixLib.buildOpamProject' { } ./. query).overrideScope overlay;

          devPackages' = builtins.attrValues (pkgs.lib.getAttrs (builtins.attrNames devPackagesQuery) scope);

          packages = pkgs.lib.getAttrs (builtins.attrNames localPackagesQuery) scope;
        in
        {
          legacyPackages = scope;
          devPackages = devPackages';
          inherit packages;
        };

      perSystem = makeOpamPkgs {
        ocamlVersion = "4.14.1";
        devPackages = {
          ocaml-lsp-server = "*";
          ocamlformat = "*";
          utop = "*";
        };
      };

      overlay = final: prev: { nene = (perSystem prev.system).packages.nene; };
    in
    {
      nixosModules = rec {
        nene = {
          nixpkgs.overlays = [ overlay ];
          imports = [ ./nix/module.nix ];
        };

        default = nene;
      };
    }
    //
      flake-utils.lib.eachSystem
        [
          "x86_64-linux"
          "aarch64-linux"
        ]
        (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
            };

            p = perSystem system;
          in
          {
            packages = p.packages;

            devShells.default = pkgs.mkShell {
              inputsFrom = builtins.attrValues p.packages;
              buildInputs = p.devPackages;
            };
          }
        );
}
