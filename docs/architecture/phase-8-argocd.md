# Phase 8 layout

Use this structure:

```text
deploy/
├── argocd/
│   ├── install/
│   │   └── README.md
│   ├── projects/
│   │   └── atlas-project.yaml
│   ├── applications/
│   │   ├── root-app.yaml
│   │   └── dev-api.yaml
│   └── README.md
```

This phase assumes your Kubernetes manifests already live in the repo and Argo CD will reconcile them from Git. Argo CD continuously compares live cluster state to the Git-defined desired state and marks drift as `OutOfSync`. ([Argo CD][2])

---

# 1. Install Argo CD

Argo CD’s getting started flow installs into the `argocd` namespace by applying the official install manifest. ([Argo CD][3])

Run:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Then verify:

```bash
kubectl get pods -n argocd
```

Wait until the Argo CD components are running.

For local access during setup, port-forward the API server:

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443
```

If you want the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode && echo
```

That initial secret name and port-forward pattern are part of the standard Argo CD getting-started workflow. ([Argo CD][3])

---

# 2. Create the AppProject

Projects are Argo CD’s way to group apps and restrict what repos, destinations, and resource types they may use. That is the right baseline when you want platform discipline instead of an everything-goes setup. ([Argo CD][4])

## `deploy/argocd/projects/atlas-project.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: atlas
  namespace: argocd
spec:
  description: Atlas Platform project

  sourceRepos:
    - "https://github.com/YOUR_GITHUB_USERNAME/Atlas-Platform.git"

  destinations:
    - namespace: atlas-dev
      server: https://kubernetes.default.svc
    - namespace: atlas-staging
      server: https://kubernetes.default.svc
    - namespace: atlas-prod
      server: https://kubernetes.default.svc

  clusterResourceWhitelist:
    - group: "*"
      kind: "*"

  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
```

Replace the Git URL with your actual repo URL.

Apply it:

```bash
kubectl apply -f deploy/argocd/projects/atlas-project.yaml
```

---

# 3. Create the dev application

Argo CD `Application` resources define the Git source, target revision, destination cluster/namespace, and sync policy. Auto-sync is configured under `spec.syncPolicy.automated`. ([Argo CD][5])

Since you said **sync dev first**, this app should point only at the dev manifests and enable auto-sync.

I’m assuming your dev deployment path will be the overlay path, not the base path, because that is the correct GitOps model once overlays exist.

## `deploy/argocd/applications/dev-api.yaml`

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
    repoURL: "https://github.com/YOUR_GITHUB_USERNAME/Atlas-Platform.git"
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

Why this shape:

- `finalizers` enables cascading deletion behavior when desired. Argo CD documents that finalizer on `Application`. ([Argo CD][5])
- `automated.prune` and `selfHeal` are the standard auto-sync controls. ([Argo CD][6])

Replace the repo URL with your actual repo.

---

# 4. Use App-of-Apps

Argo CD documents cluster bootstrapping as a declarative pattern, and App-of-Apps is a standard way to have one root application manage child applications. Argo CD’s docs and command examples explicitly refer to this pattern. ([Argo CD][7])

For now, your root app can manage just the dev child app.

## `deploy/argocd/applications/root-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: atlas-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: atlas

  source:
    repoURL: "https://github.com/YOUR_GITHUB_USERNAME/Atlas-Platform.git"
    targetRevision: main
    path: deploy/argocd/applications

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Important:

- this directory should contain only the child apps you want the root app to manage
- if you keep `root-app.yaml` in the same folder, you should **apply the root app manually once** and then let it manage the child apps, or move child apps into a subfolder like `deploy/argocd/apps/`

The cleaner layout is actually this:

```text
deploy/argocd/
├── projects/
│   └── atlas-project.yaml
├── root/
│   └── root-app.yaml
└── apps/
    └── dev-api.yaml
```

If you want the safest layout, use that instead. Then `root-app.yaml` points to `deploy/argocd/apps`.

---

# 5. Recommended final layout

Use this, because it avoids the root app trying to manage itself:

```text
deploy/
└── argocd/
    ├── install/
    │   └── README.md
    ├── projects/
    │   └── atlas-project.yaml
    ├── root/
    │   └── root-app.yaml
    ├── apps/
    │   └── dev-api.yaml
    └── README.md
```

## `deploy/argocd/root/root-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: atlas-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: atlas

  source:
    repoURL: "https://github.com/YOUR_GITHUB_USERNAME/Atlas-Platform.git"
    targetRevision: main
    path: deploy/argocd/apps

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## `deploy/argocd/apps/dev-api.yaml`

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
    repoURL: "https://github.com/YOUR_GITHUB_USERNAME/Atlas-Platform.git"
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

---

# 6. Apply Argo CD resources

Apply in this order:

```bash
kubectl apply -f deploy/argocd/projects/atlas-project.yaml
kubectl apply -f deploy/argocd/root/root-app.yaml
```

At that point, the root app should create and manage the dev app.

Verify:

```bash
kubectl get applications -n argocd
```

You should see:

- `atlas-root`
- `atlas-dev-api`

Then inspect:

```bash
kubectl describe application atlas-root -n argocd
kubectl describe application atlas-dev-api -n argocd
```

---

# 7. README for this phase

## `deploy/argocd/README.md`

````md
# Argo CD GitOps Setup

This directory contains the Phase 8 GitOps setup for Atlas Platform.

## Purpose

Argo CD becomes the deployment reconciler for the cluster.

Instead of manually running `kubectl apply` for application changes, Git becomes the source of truth and Argo CD continuously reconciles the cluster to match the manifests in this repository.

## Structure

- `projects/` contains Argo CD AppProjects
- `root/` contains the root App-of-Apps application
- `apps/` contains child Argo CD applications

## Current scope

This phase syncs **dev first**.

- `atlas-dev-api` is managed by Argo CD
- `staging` and `prod` are not auto-synced yet

## Install Argo CD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
````

## Apply project and root app

```bash
kubectl apply -f deploy/argocd/projects/atlas-project.yaml
kubectl apply -f deploy/argocd/root/root-app.yaml
```

## Verify

```bash
kubectl get applications -n argocd
kubectl get pods -n argocd
```

````

---

# 8. Senior-level operating model

This is the right progression:

- Phase 7 builds and pushes immutable images
- Phase 8 makes Argo CD the reconciler
- dev gets auto-sync first
- staging/prod stay manual until promotion rules are in place

That lines up with Argo CD’s declarative model and sync policy design. :contentReference[oaicite:9]{index=9}

---

# 9. One important correction before Phase 8 is truly complete

Your `dev-api` app points to:

```text
deploy/k8s/overlays/dev
````
