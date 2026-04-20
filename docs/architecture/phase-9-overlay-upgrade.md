Good. We do **Phase 9 — Kustomize overlays + image flow**.

This is where the platform starts behaving like a real delivery system.

Right now:

- GitHub Actions can build and push images
- Argo CD can watch Git
- EKS can run workloads

But the missing piece is:

```text
new image built → Git desired state updated → Argo CD syncs it
```

That is this phase.

---

# Phase 9 goal

We will build a proper manifest structure so that:

- `base/` contains shared workload definitions
- `overlays/dev` contains dev-specific config
- `overlays/staging` contains staging-specific config
- `overlays/prod` contains prod-specific config
- Argo CD points at `overlays/dev`
- CI can later update the dev image tag in Git

This is the bridge between CI and GitOps.

---

# What you will learn

This phase teaches:

- why base vs overlays matters
- why environment config should not duplicate everything
- how Kustomize composes manifests
- how image tags are controlled declaratively
- how Argo CD should consume overlays, not raw manifests

---

# Final folder structure for this phase

Use this:

```text
deploy/
└── k8s/
    ├── base/
    │   ├── configmap.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── kustomization.yaml
    │
    └── overlays/
        ├── dev/
        │   ├── kustomization.yaml
        │   └── patch-configmap.yaml
        │
        ├── staging/
        │   ├── kustomization.yaml
        │   └── patch-configmap.yaml
        │
        └── prod/
            ├── kustomization.yaml
            └── patch-configmap.yaml
```

You already have `deploy/k8s/base`, so we are extending what exists, not changing direction.

---

# Design rule for this phase

## Base

Base contains what is common everywhere:

- deployment structure
- service
- configmap shape
- probes
- container port
- labels

## Overlays

Overlays contain what changes per environment:

- namespace
- image tag
- image repo if needed
- environment values
- replica count

This is the correct Kustomize model.

---

# Step 1 — base manifests

We will make base environment-agnostic as much as possible.

## `deploy/k8s/base/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
  labels:
    app.kubernetes.io/name: atlas-api
    app.kubernetes.io/part-of: atlas-platform
data:
  NODE_ENV: "development"
  APP_VERSION: "v1"
  PORT: "3303"
```

---

## `deploy/k8s/base/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-api
  labels:
    app.kubernetes.io/name: atlas-api
    app.kubernetes.io/part-of: atlas-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: atlas-api
  template:
    metadata:
      labels:
        app.kubernetes.io/name: atlas-api
        app.kubernetes.io/part-of: atlas-platform
    spec:
      containers:
        - name: atlas-api
          image: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:v1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3303
          envFrom:
            - configMapRef:
                name: atlas-api-config
          readinessProbe:
            httpGet:
              path: /health
              port: 3303
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 3303
            initialDelaySeconds: 10
            periodSeconds: 15
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

---

## `deploy/k8s/base/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: atlas-api
  labels:
    app.kubernetes.io/name: atlas-api
    app.kubernetes.io/part-of: atlas-platform
spec:
  selector:
    app.kubernetes.io/name: atlas-api
  ports:
    - name: http
      port: 80
      targetPort: 3303
  type: ClusterIP
```

---

## `deploy/k8s/base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - configmap.yaml
  - deployment.yaml
  - service.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

---

# Step 2 — dev overlay

This is what Argo CD should point to first.

## `deploy/k8s/overlays/dev/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: atlas-dev

resources:
  - ../../base

patches:
  - path: patch-configmap.yaml

images:
  - name: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: v1

replicas:
  - name: atlas-api
    count: 2
```

---

## `deploy/k8s/overlays/dev/patch-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
data:
  NODE_ENV: "development"
  APP_VERSION: "v1"
  PORT: "3303"
```

---

# Step 3 — staging overlay

## `deploy/k8s/overlays/staging/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: atlas-staging

resources:
  - ../../base

patches:
  - path: patch-configmap.yaml

images:
  - name: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: v1

replicas:
  - name: atlas-api
    count: 2
```

---

## `deploy/k8s/overlays/staging/patch-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
data:
  NODE_ENV: "staging"
  APP_VERSION: "v1"
  PORT: "3303"
```

---

# Step 4 — prod overlay

## `deploy/k8s/overlays/prod/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: atlas-prod

resources:
  - ../../base

patches:
  - path: patch-configmap.yaml

images:
  - name: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: v1

replicas:
  - name: atlas-api
    count: 3
```

---

## `deploy/k8s/overlays/prod/patch-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
data:
  NODE_ENV: "production"
  APP_VERSION: "v1"
  PORT: "3303"
```

---

# Step 5 — validate overlays locally

Before Argo CD touches anything, render them yourself.

## Render dev

```bash
kubectl kustomize deploy/k8s/overlays/dev
```

## Render staging

```bash
kubectl kustomize deploy/k8s/overlays/staging
```

## Render prod

```bash
kubectl kustomize deploy/k8s/overlays/prod
```

This lets you inspect the fully rendered YAML before applying.

---

# Step 6 — apply dev overlay manually once

Before relying on Argo CD, test the overlay directly.

```bash
kubectl apply -k deploy/k8s/overlays/dev
```

Then verify:

```bash
kubectl get all -n atlas-dev
kubectl get configmap -n atlas-dev
kubectl describe configmap atlas-api-config -n atlas-dev
```

Test:

```bash
kubectl port-forward svc/atlas-api 8080:80 -n atlas-dev
```

Then:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/version
```

You should see:

- healthy response
- environment should show dev/development depending on your app output

---

# Step 7 — align Argo CD app with dev overlay

This is why the Argo CD app was pointing to:

```yaml
path: deploy/k8s/overlays/dev
```

Now it makes sense.

Your current Argo CD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: atlas-dev-api
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: atlas

  source:
    repoURL: "https://github.com/Richpong212/Atlas-Platform.git"
    targetRevision: main
    path: deploy/k8s/overlays/dev

  destination:
    server: https://kubernetes.default.svc
    namespace: atlas-dev

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
```

Now Argo CD is watching the correct dev overlay.

---

# Step 8 — how image flow will work

Here is the important mental model.

## Today

You push image:

```text
atlas-dev-api:<sha>
```

But Argo CD only deploys what Git says.

So if Git still says:

```yaml
newTag: v1
```

Argo CD will keep deploying `v1`, not the new SHA.

That means CI must later update:

```yaml
deploy/k8s/overlays/dev/kustomization.yaml
```

from:

```yaml
newTag: v1
```

to:

```yaml
newTag: <new-commit-sha>
```

Then:

- Git changes
- Argo CD detects change
- Argo CD syncs new image

That is the exact GitOps loop.

---

# Step 9 — why this phase matters

This phase is where you stop thinking:

```text
image pushed = deployed
```

That is false in GitOps.

In GitOps:

```text
image pushed + Git desired state updated = deployed
```

That distinction is huge.

---

# Step 10 — recommended README for this phase

## `deploy/k8s/README.md`

````md
# Atlas Platform Kubernetes Manifests

This directory contains the Kustomize structure for Atlas Platform workloads.

## Structure

- `base/` contains shared manifests
- `overlays/dev` contains dev-specific settings
- `overlays/staging` contains staging-specific settings
- `overlays/prod` contains prod-specific settings

## Why this exists

We do not duplicate full manifests for each environment.

Instead:

- base defines the common workload shape
- overlays define what changes by environment

This keeps the platform maintainable and makes GitOps promotion clearer.

## Render manifests

```bash
kubectl kustomize deploy/k8s/overlays/dev
```
````

## Apply dev manually

```bash
kubectl apply -k deploy/k8s/overlays/dev
```

## GitOps model

Argo CD watches the overlay path for an environment.

For dev:

- source path: `deploy/k8s/overlays/dev`
- destination namespace: `atlas-dev`

When the image tag in the overlay changes in Git, Argo CD syncs the cluster to match.

```

---

# Step 11 — what comes next after this

Once this is in place, the next logical phase is:

## Phase 10 — CI updates the dev overlay automatically

That means:
- GitHub Actions builds image
- pushes image to ECR
- updates `newTag` in `deploy/k8s/overlays/dev/kustomization.yaml`
- commits the change
- Argo CD syncs it automatically

That is the real CI → GitOps bridge.

---

# What you should do right now

In order:

1. create the overlay files
2. render them with `kubectl kustomize`
3. apply dev overlay manually
4. verify app works
5. confirm Argo CD is pointing at `deploy/k8s/overlays/dev`

Once that works, we move to automating the image tag update in Git.
```
