Good. We clean it first, then move.

# Phase 10 — CI updates the dev overlay automatically

This phase completes the loop:

```text
GitHub Actions builds image
→ pushes image to ECR
→ updates dev overlay tag in Git
→ commits and pushes
→ Argo CD sees Git change
→ syncs atlas-dev
```

That is real GitOps delivery.

## What we will add

- update `deploy/k8s/overlays/dev/kustomization.yaml`
- commit the new image tag
- push back to `main`

## Important note

For this to work, the GitHub Actions job needs permission to push back to the repo.

So in the workflow, we add:

```yaml
permissions:
  contents: write
```

not just `read`.

# Your current dev overlay

You already have something like this:

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

This is exactly what CI should edit.

# Updated GitHub Actions workflow

Use this as your new workflow.

## `.github/workflows/api-build.yml`

```yaml
name: Atlas API Build and Push

on:
  push:
    branches:
      - main
    paths:
      - "services/atlas-api/**"
      - "deploy/k8s/overlays/dev/**"
      - ".github/workflows/api-build.yml"
  workflow_dispatch:

permissions:
  contents: write

env:
  AWS_REGION: ${{ secrets.AWS_REGION }}
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  ECR_REPOSITORY: ${{ secrets.AWS_ECR_REPO }}
  SERVICE_DIR: services/atlas-api

jobs:
  build-test-scan-push-update-dev:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Node.js
        uses: actions/setup-node@v6
        with:
          node-version: "20"
          cache: "npm"
          cache-dependency-path: services/atlas-api/package-lock.json

      - name: Install dependencies
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm ci

      - name: Lint
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm run lint

      - name: Test
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm test

      - name: Build app
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm run build

      - name: Resolve AWS account and registry
        id: account
        run: |
          ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
          echo "account_id=$ACCOUNT_ID" >> "$GITHUB_OUTPUT"
          echo "registry=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" >> "$GITHUB_OUTPUT"

      - name: Log in to Amazon ECR
        id: login-ecr
        run: |
          aws ecr get-login-password --region "$AWS_REGION" | \
          docker login \
            --username AWS \
            --password-stdin "${{ steps.account.outputs.registry }}"

      - name: Set image URI
        id: image
        run: |
          echo "uri=${{ steps.account.outputs.registry }}/${ECR_REPOSITORY}:${GITHUB_SHA}" >> "$GITHUB_OUTPUT"

      - name: Build Docker image
        working-directory: ${{ env.SERVICE_DIR }}
        run: |
          docker build -t atlas-api:${GITHUB_SHA} .

      - name: Tag Docker image for ECR
        run: |
          docker tag atlas-api:${GITHUB_SHA} "${{ steps.image.outputs.uri }}"

      - name: Scan image with Trivy
        uses: aquasecurity/trivy-action@0.35.0
        with:
          image-ref: "${{ steps.image.outputs.uri }}"
          format: table
          exit-code: "1"
          ignore-unfixed: true
          severity: CRITICAL,HIGH

      - name: Push image to Amazon ECR
        run: |
          docker push "${{ steps.image.outputs.uri }}"

      - name: Update dev overlay image tag
        run: |
          sed -i "s/newTag: .*/newTag: ${GITHUB_SHA}/" deploy/k8s/overlays/dev/kustomization.yaml

      - name: Show updated dev overlay
        run: |
          cat deploy/k8s/overlays/dev/kustomization.yaml

      - name: Commit and push updated dev overlay
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"

          git add deploy/k8s/overlays/dev/kustomization.yaml

          if git diff --cached --quiet; then
            echo "No changes to commit"
            exit 0
          fi

          git commit -m "chore: update dev image tag to ${GITHUB_SHA}"
          git push
```

# Why this works

After the image is pushed, this line updates the overlay:

```bash
sed -i "s/newTag: .*/newTag: ${GITHUB_SHA}/" deploy/k8s/overlays/dev/kustomization.yaml
```

So Git changes from:

```yaml
newTag: v1
```

to:

```yaml
newTag: <commit-sha>
```

Then GitHub Actions commits and pushes that back to the repo.

Argo CD is already watching:

```yaml
path: deploy/k8s/overlays/dev
```

So once that file changes in Git, Argo CD syncs the cluster.

# One thing to avoid

This workflow triggers on changes inside `deploy/k8s/overlays/dev/**`, which means the commit made by the workflow can trigger the workflow again.

To avoid pointless loops, the clean fix is to add a guard.

Use this `if` at the job level:

```yaml
if: github.actor != 'github-actions[bot]'
```

So the top of the job becomes:

```yaml
jobs:
  build-test-scan-push-update-dev:
    if: github.actor != 'github-actions[bot]'
    runs-on: ubuntu-latest
```

## Final safer workflow

Use this exact one instead:

```yaml
name: Atlas API Build and Push

on:
  push:
    branches:
      - main
    paths:
      - "services/atlas-api/**"
      - "deploy/k8s/overlays/dev/**"
      - ".github/workflows/api-build.yml"
  workflow_dispatch:

permissions:
  contents: write

env:
  AWS_REGION: ${{ secrets.AWS_REGION }}
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  ECR_REPOSITORY: ${{ secrets.AWS_ECR_REPO }}
  SERVICE_DIR: services/atlas-api

jobs:
  build-test-scan-push-update-dev:
    if: github.actor != 'github-actions[bot]'
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Node.js
        uses: actions/setup-node@v6
        with:
          node-version: "20"
          cache: "npm"
          cache-dependency-path: services/atlas-api/package-lock.json

      - name: Install dependencies
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm ci

      - name: Lint
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm run lint

      - name: Test
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm test

      - name: Build app
        working-directory: ${{ env.SERVICE_DIR }}
        run: npm run build

      - name: Resolve AWS account and registry
        id: account
        run: |
          ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
          echo "account_id=$ACCOUNT_ID" >> "$GITHUB_OUTPUT"
          echo "registry=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" >> "$GITHUB_OUTPUT"

      - name: Log in to Amazon ECR
        id: login-ecr
        run: |
          aws ecr get-login-password --region "$AWS_REGION" | \
          docker login \
            --username AWS \
            --password-stdin "${{ steps.account.outputs.registry }}"

      - name: Set image URI
        id: image
        run: |
          echo "uri=${{ steps.account.outputs.registry }}/${ECR_REPOSITORY}:${GITHUB_SHA}" >> "$GITHUB_OUTPUT"

      - name: Build Docker image
        working-directory: ${{ env.SERVICE_DIR }}
        run: |
          docker build -t atlas-api:${GITHUB_SHA} .

      - name: Tag Docker image for ECR
        run: |
          docker tag atlas-api:${GITHUB_SHA} "${{ steps.image.outputs.uri }}"

      - name: Scan image with Trivy
        uses: aquasecurity/trivy-action@0.35.0
        with:
          image-ref: "${{ steps.image.outputs.uri }}"
          format: table
          exit-code: "1"
          ignore-unfixed: true
          severity: CRITICAL,HIGH

      - name: Push image to Amazon ECR
        run: |
          docker push "${{ steps.image.outputs.uri }}"

      - name: Update dev overlay image tag
        run: |
          sed -i "s/newTag: .*/newTag: ${GITHUB_SHA}/" deploy/k8s/overlays/dev/kustomization.yaml

      - name: Commit and push updated dev overlay
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"

          git add deploy/k8s/overlays/dev/kustomization.yaml

          if git diff --cached --quiet; then
            echo "No changes to commit"
            exit 0
          fi

          git commit -m "chore: update dev image tag to ${GITHUB_SHA}"
          git push
```

# How to verify the loop

Once this runs successfully:

1. GitHub Actions pushes image to ECR
2. workflow commits updated `newTag`
3. Argo CD sees `deploy/k8s/overlays/dev` changed
4. Argo CD syncs `atlas-dev`

Check Argo CD:

```bash
kubectl get applications -n argocd
kubectl describe application atlas-dev-api -n argocd
```

Check workload:

```bash
kubectl get deployment -n atlas-dev
kubectl get pods -n atlas-dev
```

# What this phase gives you
