# Lab 10 teardown

## Render

The QuickNotes service uses a Free Render instance.

After the lab, the service can be suspended or deleted from the Render dashboard:

`quicknotes-lab10` → Settings → Suspend Service / Delete Web Service.

## Local container

The temporary local QuickNotes container used during testing can be removed with:

```bash
docker stop quicknotes-lab10-tunnel
```

If it is not running, no action is required.

## GHCR

The release images are intentionally kept in GitHub Container Registry as Lab 10 release artifacts:
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.0
ghcr.io/kriss221/devops-intro/quicknotes:v0.1.1