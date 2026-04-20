## GitHub repo settings you should use

Set these in your GitHub repo:

**Repository Variables**

- `AWS_REGION` = `us-east-1`
- `AWS_ACCOUNT_ID` = `307946673392`
- `ECR_REPOSITORY` = `atlas-dev-api`

**Repository Secret**

- `AWS_ROLE_TO_ASSUME` = your GitHub OIDC IAM role ARN

---

## `services/atlas-api/package.json`

Make sure the scripts section includes lint, test, and build:

```json
{
  "name": "atlas-api",
  "version": "1.0.0",
  "description": "Atlas API service",
  "main": "dist/index.js",
  "scripts": {
    "lint": "tsc --noEmit",
    "test": "node -e \"console.log('No tests yet - placeholder passes')\"",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "express": "^5.1.0"
  },
  "devDependencies": {
    "@types/express": "^5.0.3",
    "@types/node": "^24.7.2",
    "ts-node": "^10.9.2",
    "typescript": "^5.9.3"
  }
}
```

---

## `.github/workflows/api-build.yml`

This keeps your current direction, uses your env values, and fixes the registry login problem.

```yaml
name: Atlas API Build and Push

on:
  push:
    branches:
      - main
    paths:
      - "services/atlas-api/**"
      - ".github/workflows/api-build.yml"
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

env:
  AWS_REGION: ${{ vars.AWS_REGION }}
  AWS_ACCOUNT_ID: ${{ vars.AWS_ACCOUNT_ID }}
  ECR_REPOSITORY: ${{ vars.ECR_REPOSITORY }}
  SERVICE_DIR: services/atlas-api

jobs:
  build-test-scan-push:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

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

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: ${{ env.AWS_REGION }}
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}

      - name: Log in to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Set image URI
        id: image
        run: |
          echo "uri=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${GITHUB_SHA}" >> "$GITHUB_OUTPUT"

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
          format: "table"
          exit-code: "1"
          ignore-unfixed: true
          severity: "CRITICAL,HIGH"

      - name: Push image to Amazon ECR
        run: |
          docker push "${{ steps.image.outputs.uri }}"

      - name: Show pushed image
        run: |
          echo "Pushed image:"
          echo "${{ steps.image.outputs.uri }}"
```

This works because:

- `configure-aws-credentials` sets AWS credentials in the job environment after assuming your IAM role via OIDC. ([GitHub][1])
- `amazon-ecr-login` logs Docker into **Amazon ECR**, which avoids accidental Docker Hub auth. ([GitHub][2])
- `setup-node` supports npm caching using `cache: npm` and `cache-dependency-path`. ([GitHub][1])

---

## Why your old error happened

This part:

```text
Get "https://registry-1.docker.io/v2/": unauthorized: incorrect username or password
```

means Docker was trying to talk to Docker Hub, not ECR. That usually happens when:

- a Docker login step defaults to Docker Hub, or
- the registry target is not explicitly ECR. ([GitHub][2])

The workflow above fixes that by using the official ECR login action and by tagging the image explicitly as:

```text
307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:${GITHUB_SHA}
```

---

## What to check before rerunning

Confirm these exist in GitHub:

**Variables**

- `AWS_REGION=us-east-1`
- `AWS_ACCOUNT_ID=307946673392`
- `ECR_REPOSITORY=atlas-dev-api`

**Secret**

- `AWS_ROLE_TO_ASSUME=<your role arn>`

Also make sure your IAM role trust policy allows your GitHub repo to assume it via OIDC. GitHub’s OIDC to AWS pattern is the recommended setup for this action. ([GitHub][1])

---

## What should happen on success

The workflow will:

- install dependencies
- lint
- run the placeholder test
- build the app
- assume your AWS role
- log in to ECR
- build the Docker image
- scan it with Trivy
- push it to:

```text
307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:<commit-sha>
```
