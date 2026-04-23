- `staging`
- `prod`

without rebuilding.

That is the core rule of this phase.

# Phase 11 goal

We want this flow:

```text
CI builds image once
→ pushes image to ECR
→ updates dev overlay
→ Argo CD syncs dev

Then later:

promote same tag to staging
→ Argo CD syncs staging

Then later:

promote same tag to prod
→ Argo CD syncs prod
```

No rebuild for staging.
No rebuild for prod.

---

# What we will add

## 1. Argo CD applications

- `atlas-staging-api`
- `atlas-prod-api`

## 2. Sync policy model

- `dev` = automated
- `staging` = manual sync or promotion-triggered
- `prod` = manual only

## 3. Promotion workflows

- workflow to promote an image tag to staging
- workflow to promote an image tag to prod

## 4. Overlay-based releases

Promotion means changing only:

- `deploy/k8s/overlays/staging/kustomization.yaml`
- `deploy/k8s/overlays/prod/kustomization.yaml`

---

# Design principle for this phase

## Wrong

```text
build again for staging
build again for prod
```

## Correct

```text
build once
promote same tag through environments
```

That is what we are implementing now.

---

# Step 1 — create Argo CD app for staging

## `deploy/argocd/apps/staging-api.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: atlas-staging-api
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: atlas

  source:
    repoURL: "https://github.com/Richpong212/Atlas-Platform.git"
    targetRevision: main
    path: deploy/k8s/overlays/staging

  destination:
    server: https://kubernetes.default.svc
    namespace: atlas-staging

  syncPolicy:
    syncOptions:
      - CreateNamespace=false
```

### Why no automated sync?

Because staging is a controlled promotion environment now.
We do not want every dev build landing there automatically.

---

# Step 2 — create Argo CD app for prod

## `deploy/argocd/apps/prod-api.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: atlas-prod-api
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: atlas

  source:
    repoURL: "https://github.com/Richpong212/Atlas-Platform.git"
    targetRevision: main
    path: deploy/k8s/overlays/prod

  destination:
    server: https://kubernetes.default.svc
    namespace: atlas-prod

  syncPolicy:
    syncOptions:
      - CreateNamespace=false
```

### Why no automated sync in prod?

Because prod should move only through explicit promotion.

---

# Step 3 — ensure root app manages them

Your App-of-Apps root points to:

```text
deploy/argocd/apps
```

So once these files exist in that folder and are committed, Argo CD root should pick them up.

Verify later with:

```bash
kubectl get applications -n argocd
```

You should eventually see:

- `atlas-dev-api`
- `atlas-staging-api`
- `atlas-prod-api`

---

# Step 4 — verify staging and prod overlays are promotion-ready

We already rendered them, but let’s lock the rule:

## `deploy/k8s/overlays/staging/kustomization.yaml`

must contain:

```yaml
images:
  - name: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: v1
```

## `deploy/k8s/overlays/prod/kustomization.yaml`

must contain:

```yaml
images:
  - name: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: v1
```

That `newTag` field is what promotion updates.

---

# Step 5 — create staging promotion workflow

This workflow does not build.
It only promotes an existing image tag.

## `.github/workflows/promote-staging.yml`

```yaml
name: Promote API to Staging

on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: "Image tag to promote to staging"
        required: true
        type: string

permissions:
  contents: write

jobs:
  promote-staging:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Update staging image tag
        run: |
          sed -i "s/newTag: .*/newTag: ${{ github.event.inputs.image_tag }}/" deploy/k8s/overlays/staging/kustomization.yaml

      - name: Show updated staging overlay
        run: |
          cat deploy/k8s/overlays/staging/kustomization.yaml

      - name: Commit and push staging promotion
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"

          git add deploy/k8s/overlays/staging/kustomization.yaml
          git commit -m "chore: promote staging to ${{ github.event.inputs.image_tag }}"
          git push
```

---

# Step 6 — create prod promotion workflow

## `.github/workflows/promote-prod.yml`

```yaml
name: Promote API to Production

on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: "Image tag to promote to production"
        required: true
        type: string

permissions:
  contents: write

jobs:
  promote-prod:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Update prod image tag
        run: |
          sed -i "s/newTag: .*/newTag: ${{ github.event.inputs.image_tag }}/" deploy/k8s/overlays/prod/kustomization.yaml

      - name: Show updated prod overlay
        run: |
          cat deploy/k8s/overlays/prod/kustomization.yaml

      - name: Commit and push prod promotion
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"

          git add deploy/k8s/overlays/prod/kustomization.yaml
          git commit -m "chore: promote prod to ${{ github.event.inputs.image_tag }}"
          git push
```

---

# Step 7 — how promotion works in practice

Let’s say CI built and pushed this image tag:

```text
f145b0ad13179d7f290f6363b5018652a482e87a
```

## Promote to staging

Run the GitHub Actions workflow manually with:

```text
image_tag = f145b0ad13179d7f290f6363b5018652a482e87a
```

That changes:

```yaml
newTag: v1
```

to:

```yaml
newTag: f145b0ad13179d7f290f6363b5018652a482e87a
```

in `deploy/k8s/overlays/staging/kustomization.yaml`.

Argo CD then sees Git changed and marks staging app OutOfSync.

If you keep staging manual, you sync it intentionally.

---

## Promote to prod

Use the exact same tag in the prod promotion workflow.

That means:

- same artifact
- same image
- only environment changes

That is the proper promotion model.

---

# Step 8 — sync model

## Dev

Your dev app currently has:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

That is good.

## Staging

Leave it without `automated` for now.

## Prod

Leave it without `automated` for now.

This gives you a clean rule:

- dev = continuous
- staging = promoted
- prod = promoted

---

# Step 9 — how to sync staging and prod

Once the overlay is updated, you can sync from Argo CD UI, or from kubectl by checking app state.

To inspect:

```bash
kubectl get applications -n argocd
kubectl describe application atlas-staging-api -n argocd
kubectl describe application atlas-prod-api -n argocd
```

If you later install Argo CD CLI, you can sync from CLI too, but for now the app objects and UI are enough.

---

# Step 10 — README for this phase

## `deploy/argocd/README.md` addition

Add this section:

```md
## Promotion model

Atlas Platform uses promotion-by-tag, not rebuild-per-environment.

### Flow

1. CI builds and pushes an immutable image tag
2. Dev overlay is updated automatically
3. Argo CD syncs dev automatically
4. Staging is promoted by updating `deploy/k8s/overlays/staging/kustomization.yaml`
5. Production is promoted by updating `deploy/k8s/overlays/prod/kustomization.yaml`

### Rule

The same image tag must move through dev, staging, and prod.

No rebuild is performed during promotion.
```

---

# Step 11 — what this phase gives you

After this phase, you now have:

- dev auto-delivery
- staging controlled promotion
- prod controlled promotion
- same artifact across environments
- Git-based release movement
- Argo CD reconciling each environment separately

That is a real release system.

---

# What comes next

The next logical phase is:

# Phase 12 — Second Service: `auth-service`

Because once release flow is in place, the next platform step is to introduce a second service and deal with:

- internal service-to-service communication
- multiple repos/folders of manifests
- multi-service GitOps structure
- cross-service rollout thinking

---

# What you should do now

Create and commit:

- `deploy/argocd/apps/staging-api.yaml`
- `deploy/argocd/apps/prod-api.yaml`
- `.github/workflows/promote-staging.yml`
- `.github/workflows/promote-prod.yml`

Then verify:

```bash
kubectl get applications -n argocd
```
