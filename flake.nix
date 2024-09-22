{
  description = "A simple flake template";

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }:

    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      buildInputs = (with pkgs; [
      ]) ++ (with pkgs-unstable; [
        zig
        zls
      ]);
    in {
      devShells.${system}.default = pkgs.mkShell { inherit buildInputs; };

      formatter.${system} = pkgs.nixfmt;
    };
}
