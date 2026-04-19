# Phase 3 — same structure, corrected values

Your correct values are:

- AWS Account ID: `307946673392`
- Region: `us-east-1`
- ECR repo: `atlas-dev-api`
- ECR URI: `307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api`
- Namespace: `atlas-dev`
- Cluster: `atlas-dev-eks-cluster`

---

## Folder structure

```text
services/atlas-api/
├── src/
├── Dockerfile
├── package.json
└── tsconfig.json

k8s/atlas-api/
├── deployment.yaml
└── service.yaml
```

---

## Step 1 — Create the service

```bash
mkdir -p services/atlas-api/src
cd services/atlas-api
npm init -y
npm install express
npm install -D typescript @types/node @types/express ts-node
npx tsc --init
```

---

## `services/atlas-api/src/index.ts`

```ts
import express from "express";

const app = express();
const port = process.env.PORT || 3000;

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

app.listen(port, "0.0.0.0", () => {
  console.log(`Server running on port ${port}`);
});
```

---

## `services/atlas-api/package.json`

Just make sure your scripts section looks like this:

```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  }
}
```

If you want the full file, use this:

```json
{
  "name": "atlas-api",
  "version": "1.0.0",
  "description": "Atlas API service",
  "main": "dist/index.js",
  "scripts": {
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

## `services/atlas-api/tsconfig.json`

Use this:

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

## Build test locally

```bash
npm run build
node dist/index.js
```

Test:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/version
```

---

# Step 2 — Dockerize

## `services/atlas-api/Dockerfile`

Keeping it close to what you already had, but making it slightly better by binding correctly:

```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

RUN npm run build

EXPOSE 3000

CMD ["npm", "run", "start"]
```

---

## Build locally

```bash
docker build -t atlas-api:latest .
```

Run:

```bash
docker run -p 3000:3000 atlas-api:latest
```

---

# Step 3 — Push to ECR

## Get repo URI

```bash
aws ecr describe-repositories \
  --query "repositories[?repositoryName=='atlas-dev-api'].repositoryUri" \
  --output text
```

Expected output:

```text
307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
```

---

## Login to ECR

```bash
aws ecr get-login-password --region us-east-1 \
| docker login \
  --username AWS \
  --password-stdin 307946673392.dkr.ecr.us-east-1.amazonaws.com
```

---

## Tag + push

```bash
docker tag atlas-api:latest 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
```

---

# Step 4 — Kubernetes manifests

## Create folder

```bash
mkdir -p k8s/atlas-api
```

---

## `k8s/atlas-api/deployment.yaml`

Only correcting the registry value:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-api
  namespace: atlas-dev
  labels:
    app: atlas-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: atlas-api
  template:
    metadata:
      labels:
        app: atlas-api
    spec:
      containers:
        - name: atlas-api
          image: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
          ports:
            - containerPort: 3000
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

---

## `k8s/atlas-api/service.yaml`

No change needed:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: atlas-api
  namespace: atlas-dev
spec:
  selector:
    app: atlas-api
  ports:
    - port: 80
      targetPort: 3000
  type: ClusterIP
```

---

# Step 5 — Deploy to cluster

Make sure kubeconfig is set:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name atlas-dev-eks-cluster
```

Then apply:

```bash
kubectl apply -f k8s/atlas-api/deployment.yaml
kubectl apply -f k8s/atlas-api/service.yaml
```

---

# Step 6 — Verify

## Check pods

```bash
kubectl get pods -n atlas-dev
```

## Check logs

```bash
kubectl logs -n atlas-dev deployment/atlas-api
```

## Port forward

```bash
kubectl port-forward svc/atlas-api 8080:80 -n atlas-dev
```

Test:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/version
```

---

# Only thing corrected

The main correction you asked for was this:

## Old wrong registry

```text
961341531911.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
```

## Correct registry

```text
307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
```

That’s the one you should use everywhere in Phase 3.

---

# One important note

Your service code must listen on `0.0.0.0`, not just default localhost inside the container. That’s why I kept this line:

```ts
app.listen(port, "0.0.0.0", () => {
  console.log(`Server running on port ${port}`);
});
```

Without that, Kubernetes may not be able to reach the app properly inside the container.
