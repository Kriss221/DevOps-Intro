{
  description = "Reproducible QuickNotes build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
      };

      quicknotes = pkgs.buildGoModule {
        pname = "quicknotes";
        version = "0.1.0";

        src = ./app;

        vendorHash = null;

        env.CGO_ENABLED = "0";

        ldflags = [
          "-s"
          "-w"
        ];
      };

      dockerImage = pkgs.dockerTools.buildImage {
        name = "quicknotes";
        tag = "nix";

        copyToRoot = quicknotes;

        created = "1970-01-01T00:00:01Z";

        extraCommands = ''
          mkdir -p tmp
          chmod 1777 tmp
        '';

        config = {
          Entrypoint = [ "/bin/quicknotes" ];

          ExposedPorts = {
            "8080/tcp" = { };
          };

          User = "65532:65532";

          Env = [
            "ADDR=:8080"
            "DATA_PATH=/tmp/notes.json"
          ];
        };
      };
    in
    {
      packages.${system} = {
        quicknotes = quicknotes;
        default = quicknotes;
        docker = dockerImage;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          go
          gopls
          golangci-lint
        ];
      };
    };
}