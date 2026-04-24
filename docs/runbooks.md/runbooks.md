---

# Step 8 — Rollback runbook

## `docs/runbooks/rollback.md`

````md
# Rollback Runbook

This runbook explains how to safely rollback Atlas workloads.

## When to rollback

Rollback when:

- new pods crash
- readiness probes fail
- error rate increases after deployment
- ingress returns 5xx
- service-to-service calls fail
- Argo CD sync applies a bad version

## Check rollout status

```bash
kubectl rollout status deployment/atlas-api -n atlas-dev
```
````
