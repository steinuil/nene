{
  description = "Utility to automate downloads of torrent series";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = (import nixpkgs) { inherit system; };
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            opam
            pkg-config
            openssl
            rnix-lsp
          ];

          shellHook = "eval $(opam env)";
        };
      });
}
