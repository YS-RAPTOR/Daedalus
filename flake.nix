{
  description = "Daedalus Dependencies";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable"; };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          sdl3.dev
          directx-shader-compiler

        ];
        INCLUDE = "${pkgs.sdl3.dev}/include";
      };
    };
}
