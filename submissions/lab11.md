# Lab 11 — Reproducible Builds of QuickNotes with Nix

## Task 1 — Reproducible Go Build via Nix Flake

### Flake

The QuickNotes build is defined in the repository-root `flake.nix`.

```nix
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
    in
    {
      packages.${system} = {
        quicknotes = quicknotes;
        default = quicknotes;
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
```

`flake.lock` is committed together with the flake and pins the exact nixpkgs revision resolved from the `nixos-25.11` input.

### `vendorHash`

The first build was intentionally attempted with:

```nix
vendorHash = pkgs.lib.fakeHash;
```

However, QuickNotes currently has no external Go module dependencies:

```text
module quicknotes

go 1.24
```

`buildGoModule` therefore reported:

```text
go: no dependencies to vendor
vendor folder is empty, please set 'vendorHash = null;' in your expression
```

For this particular module there is no dependency vendor tree to hash, so the final flake uses:

```nix
vendorHash = null;
```

No application dependencies were added or changed to manufacture a vendor hash.

---

### Build

Command:

```bash
nix build .#quicknotes
```

The build completed successfully and produced:

```text
/nix/store/1ljpx7aw07wwzkaf6ym7abdkjannc59b-quicknotes-0.1.0
```

The resulting binary is:

```text
result/bin/quicknotes
```

Example:

```text
$ ls -l result/bin/
-r-xr-xr-x 1 root root 5918800 Jan 1 1970 quicknotes
```

---

### Runtime verification

The Nix-built binary was started on a separate port:

```bash
ADDR=:18081 ./result/bin/quicknotes
```

Application log:

```text
quicknotes listening on :18081 (notes loaded: 0)
```

Health check:

```bash
curl -i http://localhost:18081/health
```

Result:

```text
HTTP/1.1 200 OK
Content-Type: application/json

{"notes":0,"status":"ok"}
```

This confirms that the binary produced by the Nix derivation runs successfully.

---

### Development shell

The flake exposes a development shell containing `go`, `gopls`, and `golangci-lint`.

Verification:

```bash
nix develop -c bash -lc 'go version; gopls version; golangci-lint version'
```

Output:

```text
go version go1.27.1 linux/amd64
golang.org/x/tools/gopls v0.20.0
golangci-lint has version 2.6.2 built with go1.25.10 from v2.6.2 on 1970-01-01T00:00:00Z
```

---

### Reproducibility verification

#### Environment A — host Ubuntu system

```bash
nix build .#quicknotes
nix-store --query --hash "$(readlink result)"
```

Result:

```text
sha256:1hv80kblj0zqcz82z0wihvxz63kylgwkqqgv5naykf0ar4f26w8k
```

Store path:

```text
/nix/store/1ljpx7aw07wwzkaf6ym7abdkjannc59b-quicknotes-0.1.0
```

#### Environment B — fresh `nixos/nix` container

A fresh Nix environment was created with:

```bash
docker run --rm -it \
  -v "$PWD:/repo" \
  -w /repo \
  nixos/nix bash
```

Inside the container:

```bash
git config --global --add safe.directory /repo

nix --extra-experimental-features "nix-command flakes" \
  build .#quicknotes

nix-store --query --hash "$(readlink result)"
```

Result:

```text
sha256:1hv80kblj0zqcz82z0wihvxz63kylgwkqqgv5naykf0ar4f26w8k
```

Store path:

```text
/nix/store/1ljpx7aw07wwzkaf6ym7abdkjannc59b-quicknotes-0.1.0
```

The two independent Nix environments therefore produced identical store hashes:

```text
Environment A:
sha256:1hv80kblj0zqcz82z0wihvxz63kylgwkqqgv5naykf0ar4f26w8k

Environment B:
sha256:1hv80kblj0zqcz82z0wihvxz63kylgwkqqgv5naykf0ar4f26w8k
```

This demonstrates reproducibility of the QuickNotes Nix build.

---

## Task 1 Design Questions

### a) Why is the same Git SHA not sufficient for bit-identical `go build` outputs?

A Git SHA fixes the application source, but it does not by itself fix the complete build environment.

Two machines can use different Go toolchain versions, different dependency resolutions, environment values, filesystem paths, build metadata, or build IDs. Generated files or build steps may also include timestamps.

Therefore identical source code does not necessarily mean identical build inputs.

Nix addresses this by describing and pinning the complete build environment rather than relying only on the source revision.

---

### b) What does `vendorHash` represent?

For `buildGoModule`, `vendorHash` identifies the fixed dependency input produced from the module's Go dependencies.

It allows Nix to verify that dependency resolution produces the expected content rather than silently accepting a different set of modules.

QuickNotes currently has no external module dependencies. The first build therefore reported:

```text
go: no dependencies to vendor
vendor folder is empty, please set 'vendorHash = null;' in your expression
```

For this application, `vendorHash = null` is appropriate because there is no dependency vendor tree to hash.

If external Go dependencies are later added, the dependency set should be pinned with the corresponding `vendorHash`.

---

### c) Why is `flake.lock` important for reproducibility?

The `nixpkgs` entry in `flake.nix` points to the `nixos-25.11` branch, but a branch can continue moving over time.

`flake.lock` records the exact resolved nixpkgs revision and its integrity information. This fixes the versions of Nix packages used by the build, including the Go toolchain and build helpers.

Without `flake.lock`, another build performed later could resolve `nixos-25.11` to a newer nixpkgs revision. Even with identical QuickNotes source code, that could change compilers, tools, dependencies, or derivations and therefore change the result.

For reproducibility, the lock file must therefore be committed with the flake.

---

### d) `buildGoModule` vs `buildGoApplication`

`buildGoModule` is the standard nixpkgs helper for building Go modules. It integrates directly with the nixpkgs build system and handles Go module dependency preparation together with `vendorHash`.

Other Go application build abstractions can provide different dependency-management workflows or additional conveniences, but may require additional tooling or inputs.

For QuickNotes I chose `buildGoModule` because it is directly available from the pinned nixpkgs input, QuickNotes is a small conventional Go module, and no additional build framework is required.

This keeps the reproducible build definition small and makes the relationship between the source, Go toolchain, and Nix derivation explicit.

# Task 2 — Deterministic OCI Image

## Nix OCI image

The flake was extended with a `docker` package implemented using `pkgs.dockerTools.buildImage`.

The relevant part of `flake.nix` is:

```nix
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
```

The package is exposed as:

```nix
packages.${system} = {
  quicknotes = quicknotes;
  default = quicknotes;
  docker = dockerImage;
};
```

The image is built entirely by Nix:

```bash
nix build .#docker
```

Docker is not involved in the build itself.

---

## Image configuration and runtime verification

The resulting Nix image was loaded into Docker:

```bash
docker load < result
```

Docker reported:

```text
Loaded image: quicknotes:nix
```

The image configuration was inspected with:

```bash
docker image inspect quicknotes:nix \
  --format 'User={{.Config.User}} Entrypoint={{json .Config.Entrypoint}} ExposedPorts={{json .Config.ExposedPorts}} Env={{json .Config.Env}}'
```

Output:

```text
User=65532:65532
Entrypoint=["/bin/quicknotes"]
ExposedPorts={"8080/tcp":{}}
Env=["ADDR=:8080","DATA_PATH=/tmp/notes.json"]
```

The container was then started and the application health endpoint was checked:

```bash
docker run --rm -d --name qn-nix -p 18082:8080 quicknotes:nix
curl -i http://localhost:18082/health
```

Result:

```text
HTTP/1.1 200 OK
Content-Type: application/json

{"notes":0,"status":"ok"}
```

The running process was also verified to use a non-root user:

```bash
docker top qn-nix -eo pid,user,args
```

Output:

```text
PID     USER    COMMAND
68788   65532   /bin/quicknotes
```

Therefore the Nix-built image contains the QuickNotes binary, uses an exec-form entrypoint, exposes port 8080, and runs the application as a non-root user.

---

## Reproducibility of the Nix image

### Environment A

```bash
nix build .#docker
sha256sum result
```

Output:

```text
8867d72cfc76bd1c9303facb0d46c5eb6536becc6c624a018c98eeaa1e429251  result
```

Store path:

```text
/nix/store/czcfds08a4qbmj1mbc5pq9jjzwcpdx0f-docker-image-quicknotes.tar.gz
```

### Environment B

A second build was performed inside a fresh `nixos/nix` container:

```bash
nix --extra-experimental-features "nix-command flakes" build .#docker
sha256sum result
```

Output:

```text
8867d72cfc76bd1c9303facb0d46c5eb6536becc6c624a018c98eeaa1e429251  result
```

The store path was also identical:

```text
/nix/store/czcfds08a4qbmj1mbc5pq9jjzwcpdx0f-docker-image-quicknotes.tar.gz
```

Therefore two independent Nix environments produced exactly the same OCI image tarball:

```text
Environment A:
8867d72cfc76bd1c9303facb0d46c5eb6536becc6c624a018c98eeaa1e429251

Environment B:
8867d72cfc76bd1c9303facb0d46c5eb6536becc6c624a018c98eeaa1e429251
```

---

## Comparison with the Lab 6 Dockerfile

The original Lab 6 image was built twice from the same source and Dockerfile with caching disabled:

```bash
docker build --no-cache -t qn-lab6:run1 ./app
docker build --no-cache -t qn-lab6:run2 ./app
```

The two builds produced different image IDs:

```text
qn-lab6:run1
sha256:66cd3c190c8896d6ba8d4c0a88a3997e254d5d2d11d1b6334bbd851297a00fd3

qn-lab6:run2
sha256:6e1aa200087ba911c757fd7489b3eb8c95958f938096b75fc73246dc0c564997
```

Both images had the same size:

```text
13,821,082 bytes
approximately 13.8 MB
```

Despite using the same Git source and Dockerfile, the image IDs differed.

By comparison, the Nix image was:

```text
8,506,066 bytes
approximately 8.51 MB
```

Its compressed Nix-produced image tarball was approximately:

```text
3.1 MB
```

Thus, comparing the loaded image sizes:

```text
Nix image:          8.51 MB
Lab 6 Docker image: 13.8 MB
```

The Nix-built image was both smaller and reproducible in this experiment.

---

## Task 2 Design Questions

### e) What does `docker build` do that can introduce non-determinism?

A Dockerfile does not automatically fix every input that affects the resulting image.

For example, build steps may create files with timestamps corresponding to the time of the build. In the Lab 6 Dockerfile, the builder performs:

```dockerfile
RUN mkdir -p /runtime-data && touch /runtime-data/.keep
```

The `touch` command creates filesystem metadata based on the current time. Layer metadata and other build-generated metadata may also vary between builds.

Base image tags can also change over time unless they are pinned by immutable digest.

As a result, two executions of `docker build --no-cache` from the same source can produce different image layer contents or metadata and therefore different image IDs.

Nix instead constructs the image from explicitly defined inputs and deterministic derivations. In this lab, a fixed image creation timestamp was also used rather than the current time.

---

### f) What can a security auditor prove with a reproducible image?

A signature on an image can prove that a trusted signer approved or produced a particular image digest.

However, if the build is not reproducible, an independent auditor cannot necessarily rebuild the claimed source code and obtain the same artifact. The auditor must therefore trust more of the original build infrastructure and build process.

With a reproducible build, an auditor can independently obtain the same pinned source and dependencies, perform the build, and compare the resulting digest with the published artifact.

If the digests match, this provides evidence that the distributed image corresponds to the declared build inputs and process.

Therefore signing and reproducibility answer different questions:

- signing establishes who attested to a particular artifact;
- reproducibility allows independent verification that the artifact can be reconstructed from the declared inputs.

They can be used together for stronger supply-chain assurance.

---

### g) What is the trade-off of Nix reproducibility, and why is `docker build` still common?

The main trade-off is additional complexity.

Nix introduces its own language, package model, store, flakes, derivations, dependency pinning, and debugging workflow. Teams need to learn and maintain this additional tooling, and integrating it into an existing development and CI/CD environment can require extra work.

Dockerfiles are more widely understood and have broad support in CI systems, container registries, cloud platforms, IDEs, and deployment tooling. For many teams, writing and maintaining a Dockerfile is simpler than introducing Nix.

Therefore `docker build` remains the common default because of its familiarity and ecosystem support, while Nix provides stronger control over build inputs and reproducibility at the cost of a steeper learning curve and additional tooling.

# Bonus Task — CI-Verified Reproducibility

## CI workflow

A GitHub Actions workflow was added at:

```text
.github/workflows/nix-repro.yml
```

The workflow runs on every push and pull request. It launches two independent build jobs on separate fresh GitHub-hosted runners.

Both jobs:

- check out the repository;
- install Nix using the Determinate Nix Installer Action pinned to the 40-character commit SHA `3138316df39ed29be04236d7ffc686fa525866aa`;
- run `nix build .#docker`;
- compute the SHA-256 digest of the resulting image tarball;
- expose that digest as a job output.

A third `compare` job consumes both outputs and fails if they differ.

The workflow is:

```yaml
name: Nix Reproducibility

on:
  push:
  pull_request:

jobs:
  build-a:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.digest.outputs.digest }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa

      - name: Build OCI image
        run: nix build .#docker

      - name: Compute digest
        id: digest
        run: |
          digest=$(sha256sum result | awk '{print $1}')
          echo "digest=$digest" >> "$GITHUB_OUTPUT"
          echo "Build A digest: $digest"

  build-b:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.digest.outputs.digest }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa

      - name: Build OCI image
        run: nix build .#docker

      - name: Compute digest
        id: digest
        run: |
          digest=$(sha256sum result | awk '{print $1}')
          echo "digest=$digest" >> "$GITHUB_OUTPUT"
          echo "Build B digest: $digest"

  compare:
    runs-on: ubuntu-latest
    needs:
      - build-a
      - build-b

    steps:
      - name: Compare digests
        env:
          DIGEST_A: ${{ needs.build-a.outputs.digest }}
          DIGEST_B: ${{ needs.build-b.outputs.digest }}
        run: |
          echo "Build A: $DIGEST_A"
          echo "Build B: $DIGEST_B"

          if [ "$DIGEST_A" != "$DIGEST_B" ]; then
            echo "Digest mismatch: reproducibility check failed."
            exit 1
          fi

          echo "Digests match: reproducibility check passed."
```

---

## Green CI run

Final successful CI run:

https://github.com/Kriss221/DevOps-Intro/actions/runs/38620300243/job/116046632337

The `compare` job reported:

```text
Build A: 8867d72cfc76bd1c9303facb0d46c5eb6536becc6c624a018c98eeaa1e429251
Build B: 8867d72cfc76bd1c9303facb0d46c5eb6536becc6c624a018c98eeaa1e429251
Digests match: reproducibility check passed.
```

Both fresh CI runners therefore independently produced the same OCI image digest.

An earlier successful run also confirmed the same result:

https://github.com/Kriss221/DevOps-Intro/actions/runs/38618213925/job/116039125296

---

## Deliberately broken CI run

To demonstrate that the CI gate can detect non-reproducibility, build A was temporarily modified so that the fixed OCI image creation timestamp was changed from:

```text
1970-01-01T00:00:01Z
```

to:

```text
1970-01-01T00:00:02Z
```

Only build A received this modification. Build B continued to build the normal flake.

The resulting CI run failed in the `compare` job:

https://github.com/Kriss221/DevOps-Intro/actions/runs/38619414729/job/116043136763

The log showed:

```text
Build A: 00d50ef6eb424160d6e04fa9f34efd45476a952b27ad6370c6e9262abeaa9a95
Build B: 8867d72cfc76bd1c9303facb0d46c5eb6536becc6c624a018c98eeaa1e429251
Digest mismatch: reproducibility check failed.
Error: Process completed with exit code 1.
```

This demonstrates that the third job detects divergent image outputs and causes the workflow to fail.

The intentional modification was then removed and the following run returned to green:

https://github.com/Kriss221/DevOps-Intro/actions/runs/38620300243/job/116046632337

---

## Bonus Design Questions

### h) What is the difference between "reproducible on my laptop" and "reproducible in CI"?

A reproducibility check performed only on one developer machine still shares a large amount of state between builds.

For example, both builds may use the same Nix store, filesystem, environment, caches, configuration, and host system. A result that is repeatable on one machine therefore does not prove that another independent environment can reproduce the artifact.

The CI workflow uses two separate fresh GitHub-hosted runners. Each runner independently checks out the repository, installs Nix, and builds the OCI image.

This makes the result stronger for a security auditor because the proof is:

- automated;
- recorded in CI logs;
- tied to a specific Git revision;
- performed on fresh independent environments;
- repeatable by future CI runs.

The auditor therefore does not have to rely only on the developer's local machine or manually reported results.

---

### i) Why use two parallel jobs instead of running `nix build` twice in one job?

Two builds inside a single job would share the same machine and Nix store.

After the first invocation:

```bash
nix build .#docker
```

the second invocation could simply reuse an already existing store path or cached derivation instead of independently rebuilding all required outputs.

That proves that Nix can retrieve the same existing artifact twice, but it is a weaker test of independent reproducibility.

Two separate CI jobs use fresh runners with separate local state. Neither job can reuse the other job's local `/nix/store`.

Therefore matching digests from the two jobs provide stronger evidence that the artifact can be independently reconstructed from the same declared inputs.

---

### j) Where can timestamps leak into the Nix image, and how does `dockerTools.buildImage` handle them?

Container image metadata and files created during the build can contain timestamps.

A particularly visible timestamp-sensitive field is the OCI image creation time. If the build were to use the current time, otherwise identical builds could produce different image metadata and therefore different digests.

In this flake the image creation timestamp is explicitly fixed:

```nix
created = "1970-01-01T00:00:01Z";
```

Therefore the current wall-clock time is not included in that field.

The image is also assembled by `dockerTools.buildImage` from Nix store inputs rather than by executing a sequence of ordinary Dockerfile layers whose commands can introduce current timestamps.

Nix derivations operate from declared inputs, and the resulting image construction avoids depending on the build time when the configuration itself does not introduce such time-dependent data.

The deliberately broken CI experiment demonstrated the importance of this timestamp: changing the fixed `created` value by only one second changed the resulting image SHA-256 digest.

Therefore timestamp-related metadata must itself be deterministic for the complete OCI image to remain reproducible.