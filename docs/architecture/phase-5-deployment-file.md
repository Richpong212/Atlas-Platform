Let’s make it.

## Phase 5 — Kubernetes Base Manifests

Recommended structure:

```text
deploy/k8s/base/
├── kustomization.yaml
├── configmap.yaml
├── deployment.yaml
└── service.yaml
```

Create them with:

```bash
mkdir -p deploy/k8s/base && \
touch deploy/k8s/base/{kustomization.yaml,configmap.yaml,deployment.yaml,service.yaml}
```

---

## `deploy/k8s/base/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
  labels:
    app.kubernetes.io/name: atlas-api
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: atlas-platform
data:
  NODE_ENV: "development"
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
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: atlas-platform
spec:
  replicas: 2
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app.kubernetes.io/name: atlas-api
      app.kubernetes.io/component: api
  template:
    metadata:
      labels:
        app.kubernetes.io/name: atlas-api
        app.kubernetes.io/component: api
        app.kubernetes.io/part-of: atlas-platform
    spec:
      securityContext:
        runAsNonRoot: true
        fsGroup: 1001
      containers:
        - name: atlas-api
          image: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 3303
              protocol: TCP
          envFrom:
            - configMapRef:
                name: atlas-api-config
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop:
                - ALL
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 2
            successThreshold: 1
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 2
            successThreshold: 1
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
            successThreshold: 1
            failureThreshold: 12
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
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: atlas-platform
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: atlas-api
    app.kubernetes.io/component: api
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
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
```

---

## Important note

These probes assume your Express app exposes:

```text
GET /health
```

So your app should have something like:

```ts
app.get("/health", (_req, res) => {
  res.status(200).json({ status: "ok" });
});
```

Without that, the pod will fail probes.

---

## Apply it

```bash
kubectl apply -k deploy/k8s/base
```

## Check it

```bash
kubectl get all
kubectl describe deployment atlas-api
kubectl get pods
```

## Senior-level note

This is a solid base, but next you’ll want overlays for:

- dev
- staging
- prod

so each environment can override:

- image tag
- replica count
- resource sizes
- config values
