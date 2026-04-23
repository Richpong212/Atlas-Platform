Good. **Next phase = Phase 13 — Frontend**.

Now the platform becomes a real chain:

```text
frontend → atlas-api → auth-service
```

This phase adds:

- a frontend service
- frontend container image
- frontend Kubernetes deployment
- frontend talking to `atlas-api`
- internal platform flow end to end

We’ll keep the same style and repo shape you’ve already been using.

---

# Phase 13 goal

Build and deploy:

- `frontend`
- exposed inside the cluster
- talks to `atlas-api`
- shows that the whole platform works end to end

---

# What this phase teaches

You learn:

- browser-facing service vs internal service
- frontend runtime config
- frontend-to-backend communication
- multi-service topology
- why service boundaries matter

---

# Target structure

```text
services/
├── atlas-api/
├── auth-service/
└── frontend/

deploy/
└── k8s/
    ├── base/
    ├── overlays/
    └── frontend/
```

---

# Build order

1. create frontend app
2. dockerize it
3. push to ECR
4. create Kubernetes manifests
5. deploy it to `atlas-dev`
6. test full flow

---

# Step 1 — Create the frontend

We keep it simple and strong: a static frontend served by Nginx.

## Commands

```bash
mkdir -p services/frontend
cd services/frontend
```

## `services/frontend/index.html`

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Atlas Platform Frontend</title>
    <style>
      body {
        font-family: Arial, sans-serif;
        margin: 0;
        padding: 2rem;
        background: #0f172a;
        color: #f8fafc;
      }

      .container {
        max-width: 800px;
        margin: 0 auto;
      }

      h1 {
        margin-bottom: 0.5rem;
      }

      p {
        color: #cbd5e1;
      }

      .card {
        background: #1e293b;
        border-radius: 12px;
        padding: 1.5rem;
        margin-top: 1.5rem;
      }

      button {
        background: #2563eb;
        color: white;
        border: none;
        padding: 0.75rem 1rem;
        border-radius: 8px;
        cursor: pointer;
        font-size: 1rem;
      }

      button:hover {
        background: #1d4ed8;
      }

      pre {
        background: #020617;
        color: #e2e8f0;
        padding: 1rem;
        border-radius: 8px;
        overflow: auto;
        margin-top: 1rem;
      }

      .status {
        margin-top: 1rem;
        font-weight: bold;
      }

      .ok {
        color: #22c55e;
      }

      .fail {
        color: #ef4444;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <h1>Atlas Platform</h1>
      <p>Frontend → API → Auth Service</p>

      <div class="card">
        <button id="checkBtn">Run End-to-End Check</button>
        <div id="status" class="status"></div>
        <pre id="output">No request made yet.</pre>
      </div>
    </div>

    <script>
      const button = document.getElementById("checkBtn");
      const output = document.getElementById("output");
      const status = document.getElementById("status");

      button.addEventListener("click", async () => {
        status.textContent = "Checking platform...";
        status.className = "status";
        output.textContent = "Loading...";

        try {
          const response = await fetch("/api/auth-check");
          const data = await response.json();

          if (!response.ok) {
            throw new Error(JSON.stringify(data));
          }

          status.textContent = "Platform flow is working";
          status.className = "status ok";
          output.textContent = JSON.stringify(data, null, 2);
        } catch (error) {
          status.textContent = "Platform flow failed";
          status.className = "status fail";
          output.textContent = String(error);
        }
      });
    </script>
  </body>
</html>
```

---

# Step 2 — Nginx config

We want frontend requests to `/api/...` to go to `atlas-api`.

## `services/frontend/nginx.conf`

```nginx
server {
    listen 8080;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri /index.html;
    }

    location /api/ {
        proxy_pass http://atlas-api.atlas-dev.svc.cluster.local/;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

This means:

- browser hits frontend
- frontend proxies `/api/*` to internal API service
- browser does not need to know cluster DNS

---

# Step 3 — Dockerfile

## `services/frontend/Dockerfile`

```dockerfile
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080
```

---

# Step 4 — ECR repo

Check whether it already exists:

```bash
aws ecr describe-repositories \
  --query "repositories[?repositoryName=='atlas-dev-frontend'].repositoryUri" \
  --output text
```

If missing:

```bash
aws ecr create-repository \
  --repository-name atlas-dev-frontend \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability IMMUTABLE
```

---

# Step 5 — Build and push frontend image

From `services/frontend`:

```bash
docker build -t atlas-frontend:v1 .
docker tag atlas-frontend:v1 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-frontend:v1
docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-frontend:v1
```

---

# Step 6 — Kubernetes manifests

## Create folder

```bash
mkdir -p deploy/k8s/frontend
```

## `deploy/k8s/frontend/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-frontend
  namespace: atlas-dev
  labels:
    app.kubernetes.io/name: atlas-frontend
    app.kubernetes.io/part-of: atlas-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: atlas-frontend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: atlas-frontend
        app.kubernetes.io/part-of: atlas-platform
    spec:
      containers:
        - name: atlas-frontend
          image: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-frontend:v1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 15
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "300m"
              memory: "256Mi"
```

## `deploy/k8s/frontend/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: atlas-frontend
  namespace: atlas-dev
  labels:
    app.kubernetes.io/name: atlas-frontend
    app.kubernetes.io/part-of: atlas-platform
spec:
  selector:
    app.kubernetes.io/name: atlas-frontend
  ports:
    - name: http
      port: 80
      targetPort: 8080
  type: ClusterIP
```

---

# Step 7 — Deploy frontend

```bash
kubectl apply -f deploy/k8s/frontend/deployment.yaml
kubectl apply -f deploy/k8s/frontend/service.yaml
```

Verify:

```bash
kubectl get pods -n atlas-dev
kubectl get svc -n atlas-dev
```

You should now see:

- `atlas-api`
- `atlas-auth-service`
- `atlas-frontend`

---

# Step 8 — Verify full flow

Port-forward frontend:

```bash
kubectl port-forward svc/atlas-frontend 8080:80 -n atlas-dev
```

Open:

```text
http://localhost:8080
```

Then click:

**Run End-to-End Check**

Expected flow:

```text
frontend
→ /api/auth-check
→ atlas-api
→ auth-service
→ response back to frontend
```

If everything works, you have a real multi-service platform running.

---

# Step 9 — What this phase gives you

You now have:

- browser-facing frontend
- internal API
- internal auth service
- service-to-service communication
- end-to-end platform flow

That is no longer “a Kubernetes toy project.”

That is a real platform baseline.

---

# Step 10 — Next phase

The next logical phase is:

# Phase 14 — Ingress + External Access + Cleaner Traffic Model

Because right now you are still using `port-forward`.

Next we should add:

- Ingress controller or ALB ingress
- public entry to frontend
- internal-only API/auth
- cleaner traffic model

That gives you:

```text
internet → frontend ingress → frontend
frontend → api
api → auth-service
```

That is the right next infrastructure/application boundary step.

If you want, I’ll give you the **full Phase 13 files in one clean block** or we go straight into **Phase 14**.
