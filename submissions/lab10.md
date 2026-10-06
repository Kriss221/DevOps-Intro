# Lab 10 — Cloud Computing

## Task 1 — CI-Automated Push to `ghcr.io`

### Release workflow

The release workflow is located at:

```text
.github/workflows/release.yml
```

It is triggered by Git tags matching `v*`, builds the QuickNotes image from `app/`, and pushes two tags to GitHub Container Registry:

- the immutable release tag, for example `v0.1.0`;
- `latest`.

The workflow uses only the required permissions:

```yaml
permissions:
  contents: read
  packages: write
```

All third-party GitHub Actions are pinned by a full 40-character commit SHA.

The release workflow uses the repository-scoped `GITHUB_TOKEN` to authenticate to GHCR.

---

### Release tag

The release tag created for this lab is:

```text
v0.1.0
```

The tag is signed.

Verification:

```text
$ git tag -v v0.1.0

object 6c2ca3b8ade6cb7f6702eaead7c56d69a63005b5
type commit
tag v0.1.0
tagger kriss <kristinsoll221@gmail.com>

Lab 10 release
Good "git" signature for k.soloveva@innopolis.university with ED25519 key
```

---

### Registry image

The released image is available at:

```text
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
```

The workflow also publishes:

```text
ghcr.io/kriss221/devops-intro/quicknotes:latest
```

Image digest:

```text
sha256:cdfcba20e114d16f10b7b7951e039cf8d211bbc377c37f952f68e83bdd5cce0f
```

---

### Successful release run

The release workflow completed successfully for tag `v0.1.0`.

GitHub Actions run:

https://github.com/Kriss221/DevOps-Intro/actions/runs/37495797595

---

### Public pull verification

To verify that the image is publicly pullable without GHCR authentication, I logged out from GHCR, removed the locally tagged image, and pulled it again.

```text
$ docker logout ghcr.io
Removing login credentials for ghcr.io

$ docker image rm ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
Untagged: ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
Untagged: ghcr.io/kriss221/devops-intro/quicknotes@sha256:cdfcba20e114d16f10b7b7951e039cf8d211bbc377c37f952f68e83bdd5cce0f

$ docker pull ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
v0.1.0: Pulling from kriss221/devops-intro/quicknotes
...
Digest: sha256:cdfcba20e114d16f10b7b7951e039cf8d211bbc377c37f952f68e83bdd5cce0f
Status: Downloaded newer image for ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
```

This confirms that the package can be pulled without authentication.

---

### Design questions

#### a) OIDC vs `GITHUB_TOKEN`

For publishing an image to GHCR from the same GitHub repository, `GITHUB_TOKEN` with `packages: write` is sufficient because GitHub automatically creates a short-lived token for the workflow run.

OIDC is more useful when GitHub Actions needs to authenticate to an external cloud provider or another service. Instead of storing a long-lived cloud credential as a GitHub secret, the workflow can prove its GitHub identity and exchange it for short-lived credentials issued by the external platform.

Therefore, `GITHUB_TOKEN` is appropriate for pushing to GHCR in this repository, while OIDC becomes more valuable when authenticating to external infrastructure such as AWS, Azure, or GCP.

#### b) `latest` tag vs immutable version tag

The version tag such as `v0.1.0` provides a stable release reference. It is useful for reproducible deployments, debugging, rollbacks, and knowing exactly which application version is running.

The `latest` tag is mutable, but it is still useful as a convenient pointer to the most recent release. For example, a developer can pull the newest image without first finding the latest version number.

For production deployments where reproducibility matters, the immutable version tag should be preferred. `latest` is mainly a convenience alias.

#### c) Why only `packages: write`

This follows the principle of least privilege.

The release workflow only needs to:

- read repository contents;
- publish container packages.

Therefore:

```yaml
contents: read
packages: write
```

is sufficient.

Using broader permissions such as `write: all` would increase the possible impact of a compromised workflow, third-party action, or malicious command. Such a token could potentially modify repository contents, pull requests, issues, or other GitHub resources unrelated to container publishing.

Restricting the token to the minimum necessary permissions limits the blast radius of such a compromise.

---

# Task 2 — Deploy to Render

## Deployment option

Option used:

```text
Render — Free Web Service
```

I used Option A because Render allowed me to create a Free Web Service without requesting card verification.

The service uses the prebuilt QuickNotes image from GitHub Container Registry rather than rebuilding the application from the repository.

---

## Render service configuration

Service name:

```text
quicknotes-lab10
```

Public URL:

```text
https://quicknotes-lab10-9pv6.onrender.com
```

Region:

```text
Frankfurt (EU Central)
```

Instance type:

```text
Free
```

Source:

```text
Existing Image
```

Initial image:

```text
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
```

The CI deploy-hook test later redeployed the service with:

```text
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.1
```

Health check path:

```text
/health
```

Environment variables:

```text
PORT=8080
ADDR=:8080
```

The same port is configured for both Render and QuickNotes, so the application starts on the port expected by Render without requiring port auto-detection and a second deploy.

The Render configuration is also documented in:

```text
cloud/render.md
```

---

## Public service verification

### `/health`

Command:

```bash
curl -v https://quicknotes-lab10-9pv6.onrender.com/health
```

Relevant output:

```text
> GET /health HTTP/2
< HTTP/2 200
< content-type: application/json

{"notes":0,"status":"ok"}
```

### `/notes`

Command:

```bash
curl -v https://quicknotes-lab10-9pv6.onrender.com/notes
```

Relevant output:

```text
> GET /notes HTTP/2
< HTTP/2 200
< content-type: application/json

[]
```

Both endpoints were therefore publicly reachable over HTTPS.

---

## Render deploy log

The initial deployment completed successfully.

Relevant application log:

```text
quicknotes listening on :8080
(notes loaded: 0)
```

Render also detected the expected port:

```text
Detected service running on port 8080
```

Because `PORT=8080` and `ADDR=:8080` were configured before the first deployment, there was no `New primary port detected` mismatch restart.

---

## Deploy from CI using a Render deploy hook

The Render deploy hook URL is stored as a GitHub Actions repository secret:

```text
RENDER_DEPLOY_HOOK_URL
```

The hook URL itself is not committed to the repository.

The following step was added to `.github/workflows/release.yml` after the GHCR push:

```yaml
- name: Deploy to Render
  env:
    RENDER_DEPLOY_HOOK_URL: ${{ secrets.RENDER_DEPLOY_HOOK_URL }}
  run: |
    IMAGE="ghcr.io/${GITHUB_REPOSITORY,,}/quicknotes"
    VERSION="${GITHUB_REF_NAME}"

    curl --fail-with-body --silent --show-error \
      --get \
      --data-urlencode "imgURL=${IMAGE}:${VERSION}" \
      "${RENDER_DEPLOY_HOOK_URL}"
```

The resulting release flow is:

```text
Git tag
→ GitHub Actions
→ build QuickNotes image
→ push version tag and latest to GHCR
→ call Render deploy hook
→ Render redeploys the tagged image
```

To verify this flow, I created and pushed the signed tag:

```text
v0.1.1
```

GitHub Actions release run:

https://github.com/Kriss221/DevOps-Intro/actions/runs/37501814009

The workflow completed successfully.

Render then created a new deployment for `v0.1.1` with:

```text
TRIGGER: Deploy Hook
```

The deploy completed successfully in approximately:

```text
10.7 s
```

This demonstrates that pushing a release tag can automatically publish the image and redeploy Render through CI.

---

## Warm latency

Five consecutive warm requests were made to:

```text
https://quicknotes-lab10-9pv6.onrender.com/health
```

using:

```bash
for i in {1..5}; do
  curl -w '%{time_total}\n' -o /dev/null -s \
    https://quicknotes-lab10-9pv6.onrender.com/health
done
```

Measurements:

```text
1.365002 s
0.763741 s
0.489012 s
0.476258 s
0.503666 s
```

Sorted:

```text
0.476258
0.489012
0.503666
0.763741
1.365002
```

Therefore:

```text
Warm p50 = 0.503666 s
```

---

## Cold-start latency

The Render Free service was allowed to spin down between measurements.

Render logs confirmed the shutdown and restart behavior with entries such as:

```text
shutting down
```

followed, after a request woke the service, by:

```text
quicknotes listening on :8080 (notes loaded: 0)
```

The three measured cold starts were:

```text
Cold start #1 = 63.987377 s
Cold start #2 = 12.909311 s
Cold start #3 = 14.026297 s
```

The measurements vary significantly because the amount of work required to wake or provision a free instance is not constant.

All three measurements were taken after the service had spun down and the restart was confirmed in Render logs.

---

## Note persistence after spin-down

Before allowing the service to spin down, I created a note.

Request:

```bash
curl -i -X POST \
  https://quicknotes-lab10-9pv6.onrender.com/notes \
  -H 'Content-Type: application/json' \
  -d '{"title":"Lab 10 persistence test","body":"Created before Render spin-down"}'
```

Response:

```text
HTTP/2 201
```

```json
{
  "id": 1,
  "title": "Lab 10 persistence test",
  "body": "Created before Render spin-down",
  "created_at": "2026-10-06T17:20:15.221420415Z"
}
```

Immediately afterwards, `GET /notes` returned:

```json
[
  {
    "id": 1,
    "title": "Lab 10 persistence test",
    "body": "Created before Render spin-down",
    "created_at": "2026-10-06T17:20:15.221420415Z"
  }
]
```

After Render had shut down and started a new instance, `/health` returned:

```json
{"notes":0,"status":"ok"}
```

and:

```bash
curl -s https://quicknotes-lab10-9pv6.onrender.com/notes
```

returned:

```json
[]
```

The note therefore did not survive the instance restart.

Render Free does not provide a persistent disk for this service, so data written to the container's local filesystem is ephemeral. When the instance is replaced, QuickNotes starts with a new filesystem and the previously created note is lost.

The Render logs also confirmed this behavior because the restarted application reported:

```text
quicknotes listening on :8080 (notes loaded: 0)
```

---

## Design questions

### d) Render spin-down vs Cloud Run scale-to-zero

Both Render spin-down and Cloud Run scale-to-zero reduce resource usage when an application is idle and start compute again when traffic returns.

The important difference is what the platforms are optimized for.

Render's Free Web Service is primarily designed to provide simple, inexpensive application hosting. After an idle period, the service may need to restore or provision the runtime environment and start the container again. This can produce relatively long and variable wake-up times.

This was visible in my measurements:

```text
63.987377 s
12.909311 s
14.026297 s
```

Cloud Run is a serverless container platform designed around automatic request-driven scaling. Its infrastructure is specifically optimized to create and remove instances dynamically and therefore generally aims for substantially faster scale-from-zero behavior.

Render Free prioritizes simple free hosting and resource conservation, while Cloud Run is designed for production autoscaling and request-driven execution.

---

### e) Why Render injects `PORT`

A Dockerfile `EXPOSE` instruction is only image metadata. It documents the intended port but does not force the application process to bind to that port.

Render therefore provides the expected application port through the `PORT` environment variable.

QuickNotes independently uses its `ADDR` environment variable to determine its listening address.

For this deployment I configured:

```text
PORT=8080
ADDR=:8080
```

As a result, QuickNotes immediately started on:

```text
:8080
```

and Render detected:

```text
Detected service running on port 8080
```

If `PORT` and the port used by QuickNotes did not agree, Render could initially start the service with the wrong expectation, detect the actual listening port, and restart the deployment with a new primary port.

That restart adds unnecessary deployment time and makes every mismatched deployment less predictable.

Configuring both values consistently avoids that additional restart.

---

### f) Existing image vs Render building from the repository

I chose to deploy the existing image from GHCR:

```text
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
```

and later:

```text
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.1
```

This means Render runs the same release artifact that GitHub Actions built and published.

This has several advantages:

- the build occurs once in CI;
- the deployed image is reproducible;
- the immutable version tag identifies exactly what was deployed;
- the deployment artifact is the same container image that was hardened and scanned during the previous labs;
- another environment can pull exactly the same image.

If Render instead built directly from the repository, its own build cache could make deployment convenient and its build logs could make debugging easier. However, it would introduce a second independent build process.

The resulting container could therefore differ from the artifact produced and tested by the main CI pipeline.

For this lab, using the existing GHCR image provides a cleaner separation:

```text
CI builds the artifact
→ registry stores the artifact
→ Render deploys the artifact
```

The note persistence experiment also demonstrates an important consequence of the deployment model.

The note disappeared after the Render instance restarted because QuickNotes stores its data on the local container filesystem and the Free Render service has no persistent disk attached.

Therefore the container image is reproducible, but runtime data stored only inside a container instance is not persistent.
---


---

# Final artifacts

The Lab 10 submission contains:

```text
.github/workflows/release.yml
cloud/render.md
cloud/teardown.md
submissions/lab10.md
```
Release image:

```text
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
```

Release workflow run:

https://github.com/Kriss221/DevOps-Intro/actions/runs/37495797595
