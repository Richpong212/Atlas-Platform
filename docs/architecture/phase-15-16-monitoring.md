We’ll use `kube-prometheus-stack` because it gives us Prometheus, Grafana, Alertmanager, default Kubernetes dashboards/rules, and the Prometheus Operator as one maintained Helm chart. The chart is published by the Prometheus community and is designed as an end-to-end Kubernetes monitoring stack. ([Artifact Hub][1])

# What we are building now

```text
monitoring namespace
├── Prometheus
├── Grafana
├── Alertmanager
├── kube-state-metrics
├── node-exporter
└── default Kubernetes dashboards/rules
```

Then we add docs for:

```text
how to observe
how to debug
how to rollback
how to recover
```

---

# Phase 15/16 folder structure

Create:

```text
deploy/
└── monitoring/
    ├── values.yaml
    ├── install-monitoring.sh
    ├── port-forward-grafana.sh
    └── README.md

docs/
└── runbooks/
    ├── rollback.md
    ├── pod-crashloop.md
    ├── ingress-debug.md
    └── image-pull-debug.md
```

---

# Step 1 — Create monitoring namespace

```bash
kubectl create namespace monitoring
```

If it already exists:

```bash
kubectl get ns monitoring
```

---

# Step 2 — Add Helm repo

Helm is the standard package manager for Kubernetes apps, and charts define/install/upgrade Kubernetes applications. ([helm.sh][2])

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

---

# Step 3 — Create values file

## `deploy/monitoring/values.yaml`

```yaml
grafana:
  enabled: true
  adminPassword: "admin123"
  service:
    type: ClusterIP

prometheus:
  prometheusSpec:
    retention: 7d
    scrapeInterval: 30s
    evaluationInterval: 30s

alertmanager:
  enabled: true

kubeStateMetrics:
  enabled: true

nodeExporter:
  enabled: true
```

This is intentionally simple for the first install. Later we can move passwords into Secrets and add persistence.

---

# Step 4 — Install monitoring stack

## `deploy/monitoring/install-monitoring.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring

helm upgrade --install atlas-monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values deploy/monitoring/values.yaml

kubectl get pods -n monitoring
```

Make it executable:

```bash
chmod +x deploy/monitoring/install-monitoring.sh
```

Run:

```bash
./deploy/monitoring/install-monitoring.sh
```

---

# Step 5 — Verify monitoring

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

Wait until pods are running:

```bash
kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s
```

---

# Step 6 — Access Grafana

## `deploy/monitoring/port-forward-grafana.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

kubectl port-forward -n monitoring svc/atlas-monitoring-grafana 3000:80
```

Run:

```bash
chmod +x deploy/monitoring/port-forward-grafana.sh
./deploy/monitoring/port-forward-grafana.sh
```

Open:

```text
http://localhost:3000
```

Login:

```text
username: admin
password: admin123
```

---

# Step 7 — Monitoring README

## `deploy/monitoring/README.md`

````md
# Atlas Platform Monitoring

This folder installs the monitoring stack for Atlas Platform.

## What it installs

The stack installs:

- Prometheus
- Grafana
- Alertmanager
- kube-state-metrics
- node-exporter
- default Kubernetes dashboards and rules

## Why this exists

A platform is not production-ready just because workloads run.

We need visibility into:

- pod health
- deployment status
- node usage
- CPU and memory pressure
- restart loops
- failed scheduling
- cluster-level alerts

## Install

```bash
./deploy/monitoring/install-monitoring.sh
```
````

## Verify

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

## Access Grafana

```bash
./deploy/monitoring/port-forward-grafana.sh
```

Open:

```text
http://localhost:3000
```

Default credentials for this learning phase:

```text
admin / admin123
```

## Important

The password is hardcoded only for the learning phase.

Later, move it into a Kubernetes Secret or external secret manager.

````

---

# Step 8 — Rollback runbook

## `docs/runbooks/rollback.md`

```md
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
````

## Check rollout history

```bash
kubectl rollout history deployment/atlas-api -n atlas-dev
```

## Rollback using Kubernetes

```bash
kubectl rollout undo deployment/atlas-api -n atlas-dev
```

## Verify after rollback

```bash
kubectl get pods -n atlas-dev
kubectl logs -n atlas-dev deployment/atlas-api
kubectl rollout status deployment/atlas-api -n atlas-dev
```

## GitOps warning

If Argo CD is managing the app, a manual rollback may be reverted by Argo CD.

The proper GitOps rollback is:

1. revert the image tag in Git
2. commit the change
3. let Argo CD sync the desired state

## GitOps rollback example

Edit:

```text
deploy/k8s/overlays/dev/kustomization.yaml
```

Change:

```yaml
newTag: bad-sha
```

back to:

```yaml
newTag: known-good-sha
```

Then commit:

```bash
git add deploy/k8s/overlays/dev/kustomization.yaml
git commit -m "rollback: dev api to known-good-sha"
git push
```

Argo CD will sync the cluster back to the known-good version.

````

---

# Step 9 — Pod crashloop runbook

## `docs/runbooks/pod-crashloop.md`

```md
# Pod CrashLoopBackOff Runbook

## Symptoms

Pods show:

```text
CrashLoopBackOff
Error
RunContainerError
````

## Step 1: List pods

```bash
kubectl get pods -n atlas-dev
```

## Step 2: Describe the failing pod

```bash
kubectl describe pod <pod-name> -n atlas-dev
```

Look at:

- Events
- container state
- exit code
- image pull errors
- probe failures

## Step 3: Check logs

```bash
kubectl logs <pod-name> -n atlas-dev
```

If the pod has restarted:

```bash
kubectl logs <pod-name> -n atlas-dev --previous
```

## Step 4: Check config

```bash
kubectl get configmap -n atlas-dev
kubectl describe configmap atlas-api-config -n atlas-dev
```

## Step 5: Check resources

```bash
kubectl top pods -n atlas-dev
kubectl top nodes
```

## Common causes

- app starts on wrong port
- required env var missing
- image tag is wrong
- readiness/liveness probe path wrong
- service dependency unavailable
- container does not have permission to run

## Recovery

If caused by a bad image:

- rollback image tag in Git
- let Argo CD sync

````

---

# Step 10 — Image pull runbook

## `docs/runbooks/image-pull-debug.md`

```md
# Image Pull Debug Runbook

## Symptoms

Pods show:

```text
ImagePullBackOff
ErrImagePull
````

## Step 1: Describe pod

```bash
kubectl describe pod <pod-name> -n atlas-dev
```

Look for image-related events.

## Step 2: Confirm image tag exists in ECR

```bash
aws ecr describe-images \
  --repository-name atlas-dev-api \
  --region us-east-1 \
  --query "imageDetails[].imageTags" \
  --output table
```

## Step 3: Confirm deployment image

```bash
kubectl get deployment atlas-api -n atlas-dev -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
```

## Step 4: Confirm node role can pull from ECR

The EKS node role needs ECR read permissions.

Expected policy:

```text
AmazonEC2ContainerRegistryReadOnly
```

## Common causes

- image tag does not exist
- ECR repo name is wrong
- AWS region mismatch
- node role lacks ECR pull permission
- image is private and auth is missing

## Recovery

- push the missing image
- correct the image tag in Git
- confirm Argo CD syncs the corrected version

````

---

# Step 11 — Ingress debug runbook

## `docs/runbooks/ingress-debug.md`

```md
# Ingress Debug Runbook

## Symptoms

- browser cannot reach frontend
- ingress returns 404
- ingress returns 502/503
- load balancer exists but app does not respond

## Step 1: Check ingress controller

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
````

## Step 2: Check ingress resource

```bash
kubectl get ingress -n atlas-dev
kubectl describe ingress atlas-frontend-ingress -n atlas-dev
```

## Step 3: Check frontend service

```bash
kubectl get svc atlas-frontend -n atlas-dev
kubectl get endpoints atlas-frontend -n atlas-dev
```

If endpoints are empty, the service selector does not match pods.

## Step 4: Check frontend pods

```bash
kubectl get pods -n atlas-dev -l app.kubernetes.io/name=atlas-frontend
kubectl logs -n atlas-dev deployment/atlas-frontend
```

## Step 5: Test with host header

```bash
curl -H "Host: atlas-dev.local" http://<load-balancer-hostname>/
```

## Common causes

- ingress host mismatch
- service selector mismatch
- frontend pods not ready
- ingress controller not running
- load balancer still provisioning

## Recovery

Fix the broken resource in Git and let Argo CD sync.

```

---

# What this gives you

Now Atlas has:

- monitoring stack
- Grafana dashboards
- Prometheus metrics
- Alertmanager foundation
- rollback runbook
- pod debugging runbook
- image pull debugging runbook
- ingress debugging runbook

That is the point where the platform becomes **operable**.

# Next phase after this

After you install and verify monitoring, the next phase should be:

**Phase 17 — Platform hardening**

That includes:
- Pod Security Standards
- RBAC tightening
- NetworkPolicy enforcement
- secrets management
- maybe IRSA later

But first, implement this monitoring + runbook phase and verify Grafana is reachable.
::contentReference[oaicite:2]{index=2}
```

[1]: https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack?utm_source=chatgpt.com "kube-prometheus-stack 84.0.0"
[2]: https://helm.sh/?utm_source=chatgpt.com "Helm charts"
