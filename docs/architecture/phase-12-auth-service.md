# Phase 12 goal

We add a second internal service:

- `auth-service`

and make `atlas-api` talk to it.

So the platform becomes:

```text
client → atlas-api → auth-service
```

Not public-to-public.
`auth-service` should be **internal only**.

---

# What this phase teaches

This phase is important because now you learn:

- service-to-service communication
- internal DNS in Kubernetes
- internal-only service exposure
- config between services
- how one service depends on another
- how multi-service manifests should be structured

---

# What we will build

## New service

`auth-service`

Endpoints:

- `/health`
- `/validate`

## API change

`atlas-api` will call `auth-service`

Example:

- request hits `atlas-api`
- `atlas-api` calls `http://atlas-auth-service/validate`
- response returns from auth-service

---

# Target structure

We keep the same style you already have.

```text
services/
├── atlas-api/
└── auth-service/

deploy/
└── k8s/
    ├── base/
    │   ├── configmap.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── kustomization.yaml
    │
    ├── auth-service/
    │   ├── configmap.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── kustomization.yaml
    │
    └── overlays/
        ├── dev/
        ├── staging/
        └── prod/
```

To keep things clean, we should actually move toward:

```text
deploy/k8s/base/api/
deploy/k8s/base/auth-service/
```

But since you asked not to keep changing direction too much, the cleanest next step is:

- leave existing API structure alone
- add `deploy/k8s/auth-service/`
- then later normalize both into a cleaner multi-service base structure

---

# Phase 12 build order

## Step 1

Create `services/auth-service`

## Step 2

Dockerize it

## Step 3

Push image to ECR

## Step 4

Create Kubernetes deployment + service

## Step 5

Deploy it to `atlas-dev`

## Step 6

Update `atlas-api` to call it

## Step 7

Verify internal communication

---

# Step 1 — Create the auth service

## Commands

```bash
mkdir -p services/auth-service/src
cd services/auth-service
npm init -y
npm install express
npm install -D typescript @types/node @types/express ts-node
npx tsc --init
```

---

## `services/auth-service/src/index.ts`

```ts
import express from "express";

const app = express();
const port = process.env.PORT || 3304;

app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "auth-service" });
});

app.get("/validate", (_req, res) => {
  res.json({
    valid: true,
    service: "auth-service",
    message: "Token validated successfully",
  });
});

app.listen(port, "0.0.0.0", () => {
  console.log(`auth-service running on port ${port}`);
});
```

---

## `services/auth-service/package.json`

```json
{
  "name": "auth-service",
  "version": "1.0.0",
  "description": "Atlas auth service",
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

## `services/auth-service/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "rootDir": "src",
    "outDir": "dist",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
```

---

# Step 2 — Dockerfile

## `services/auth-service/Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine AS base
WORKDIR /app

FROM base AS deps
COPY package*.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-alpine AS prod-deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM gcr.io/distroless/nodejs22-debian13:nonroot AS runtime
WORKDIR /app

ENV NODE_ENV=production

COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3304

LABEL org.opencontainers.image.title="auth-service" \
      org.opencontainers.image.description="Atlas Platform Auth service" \
      org.opencontainers.image.vendor="Codegenitor" \
      org.opencontainers.image.source="https://github.com/Richpong212/Atlas-Platform" \
      org.opencontainers.image.licenses="ISC"

CMD ["dist/index.js"]
```

---

# Step 3 — ECR

You need an ECR repo for auth-service.

If it does not exist yet, add it through CloudFormation later, but for now check:

```bash
aws ecr describe-repositories \
  --query "repositories[?repositoryName=='atlas-dev-auth-service'].repositoryUri" \
  --output text
```

If missing, create manually for now:

```bash
aws ecr create-repository \
  --repository-name atlas-dev-auth-service \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability IMMUTABLE
```

---

# Step 4 — Build and push auth-service

From `services/auth-service`:

```bash
docker build -t auth-service:v1 .
docker tag auth-service:v1 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-auth-service:v1
docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-auth-service:v1
```

---

# Step 5 — Kubernetes manifests

## Create folder

```bash
mkdir -p deploy/k8s/auth-service
```

---

## `deploy/k8s/auth-service/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: auth-service-config
  namespace: atlas-dev
  labels:
    app.kubernetes.io/name: auth-service
    app.kubernetes.io/part-of: atlas-platform
data:
  NODE_ENV: "development"
  PORT: "3304"
```

---

## `deploy/k8s/auth-service/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-auth-service
  namespace: atlas-dev
  labels:
    app.kubernetes.io/name: auth-service
    app.kubernetes.io/part-of: atlas-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: auth-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: auth-service
        app.kubernetes.io/part-of: atlas-platform
    spec:
      containers:
        - name: auth-service
          image: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-auth-service:v1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3304
          envFrom:
            - configMapRef:
                name: auth-service-config
          readinessProbe:
            httpGet:
              path: /health
              port: 3304
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 3304
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

## `deploy/k8s/auth-service/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: atlas-auth-service
  namespace: atlas-dev
  labels:
    app.kubernetes.io/name: auth-service
    app.kubernetes.io/part-of: atlas-platform
spec:
  selector:
    app.kubernetes.io/name: auth-service
  ports:
    - name: http
      port: 80
      targetPort: 3304
  type: ClusterIP
```

---

# Step 6 — Deploy auth-service

```bash
kubectl apply -f deploy/k8s/auth-service/configmap.yaml
kubectl apply -f deploy/k8s/auth-service/deployment.yaml
kubectl apply -f deploy/k8s/auth-service/service.yaml
```

Verify:

```bash
kubectl get pods -n atlas-dev
kubectl get svc -n atlas-dev
```

---

# Step 7 — Update atlas-api to call auth-service

Inside Kubernetes, the service DNS name is:

```text
http://atlas-auth-service
```

So update your `atlas-api` code.

## `services/atlas-api/src/index.ts`

Use this version:

```ts
import express from "express";

const app = express();
const port = process.env.PORT || 3303;
const authServiceUrl =
  process.env.AUTH_SERVICE_URL || "http://atlas-auth-service";

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get("/version", (_req, res) => {
  res.json({
    service: "atlas-api",
    version: "1.0.0",
    env: process.env.NODE_ENV || "dev",
  });
});

app.get("/auth-check", async (_req, res) => {
  try {
    const response = await fetch(`${authServiceUrl}/validate`);
    const data = await response.json();
    res.json({
      api: "atlas-api",
      auth: data,
    });
  } catch (error) {
    res.status(500).json({
      error: "Failed to reach auth-service",
    });
  }
});

app.listen(port, "0.0.0.0", () => {
  console.log(`Server running on port ${port}`);
});
```

Also add env in your API config so it knows the auth URL.

---

# Step 8 — add auth URL to API configmap

Wherever your API configmap is rendered, add:

```yaml
AUTH_SERVICE_URL: "http://atlas-auth-service"
```

Then rebuild and redeploy `atlas-api`.

---

# Step 9 — verify service-to-service communication

Port-forward API:

```bash
kubectl port-forward svc/atlas-api 8080:80 -n atlas-dev
```

Then test:

```bash
curl http://localhost:8080/auth-check
```

Expected result:

```json
{
  "api": "atlas-api",
  "auth": {
    "valid": true,
    "service": "auth-service",
    "message": "Token validated successfully"
  }
}
```

---

# Why this phase matters

This is the first time the platform has:

- more than one service
- internal DNS-based communication
- dependency between services
- internal-only service exposure
- multi-service deployment concerns

That is a real platform milestone.

---

# After this phase

The next logical phase is:

# Phase 13 — Frontend

Then the system becomes:

```text
frontend → atlas-api → auth-service
```

which gives you a real end-to-end stack.
