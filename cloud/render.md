# Render deployment configuration

## Service

Name:

```text
quicknotes-lab10
```

## Region 

Frankfurt (EU Central)

## Instance Type

Free

## Source

Existing Image

## Image 

ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0

## Public url 

https://quicknotes-lab10-9pv6.onrender.com

## Port configuration

PORT=8080
ADDR=:8080

quicknotes listening on :8080
(notes loaded: 0)

No New primary port detected restart was required.

## Health check 

path: /health
public verification:
GET /health
HTTP/2 200

{"notes":0,"status":"ok"}

The /notes endpoint was also publicly reachable:
GET /notes
HTTP/2 200

[]

## Deployment source choice
I used the existing immutable image from GitHub Container Registry instead of letting Render rebuild the repository.
This ensures that Render deploys the same release artifact that was built by GitHub Actions and published to GHCR:
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0

This improves reproducibility and keeps deployment tied to the image produced and verified by the CI pipeline.