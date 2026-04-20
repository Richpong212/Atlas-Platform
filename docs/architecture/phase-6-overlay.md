## Target structure

```text
deploy/k8s/
├── base/
│   ├── kustomization.yaml
│   ├── configmap.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── configmap-patch.yaml
    │   └── deployment-patch.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── configmap-patch.yaml
    │   └── deployment-patch.yaml
    └── prod/
        ├── kustomization.yaml
        ├── namespace.yaml
        ├── configmap-patch.yaml
        └── deployment-patch.yaml
```

---

# 1. Fix the base first

## `deploy/k8s/base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - configmap.yaml
  - deployment.yaml
  - service.yaml

labels:
  - pairs:
      app.kubernetes.io/name: atlas-api
      app.kubernetes.io/component: api
      app.kubernetes.io/part-of: atlas-platform

commonAnnotations:
  managed-by: kustomize
```

## `deploy/k8s/base/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
data:
  NODE_ENV: "development"
  PORT: "3303"
```

## `deploy/k8s/base/deployment.yaml`

Notice this image is neutral now.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-api
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
      containers:
        - name: atlas-api
          image: atlas-api:latest
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
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 2
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 12
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

## `deploy/k8s/base/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: atlas-api
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

# 2. Dev overlay

## `deploy/k8s/overlays/dev/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: atlas-dev
  labels:
    environment: dev
```

## `deploy/k8s/overlays/dev/configmap-patch.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
data:
  NODE_ENV: "development"
  PORT: "3303"
```

## `deploy/k8s/overlays/dev/deployment-patch.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-api
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: atlas-api
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
```

## `deploy/k8s/overlays/dev/kustomization.yaml`

This is the cleaner part: `images:`.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: atlas-dev

resources:
  - ../../base
  - namespace.yaml

patches:
  - path: configmap-patch.yaml
  - path: deployment-patch.yaml

images:
  - name: atlas-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: dev

labels:
  - pairs:
      environment: dev
```

---

# 3. Staging overlay

## `deploy/k8s/overlays/staging/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: atlas-staging
  labels:
    environment: staging
```

## `deploy/k8s/overlays/staging/configmap-patch.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
data:
  NODE_ENV: "staging"
  PORT: "3303"
```

## `deploy/k8s/overlays/staging/deployment-patch.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-api
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: atlas-api
          resources:
            requests:
              cpu: "150m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

## `deploy/k8s/overlays/staging/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: atlas-staging

resources:
  - ../../base
  - namespace.yaml

patches:
  - path: configmap-patch.yaml
  - path: deployment-patch.yaml

images:
  - name: atlas-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: staging

labels:
  - pairs:
      environment: staging
```

---

# 4. Prod overlay

## `deploy/k8s/overlays/prod/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: atlas-prod
  labels:
    environment: prod
```

## `deploy/k8s/overlays/prod/configmap-patch.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atlas-api-config
data:
  NODE_ENV: "production"
  PORT: "3303"
```

## `deploy/k8s/overlays/prod/deployment-patch.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas-api
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: atlas-api
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
```

## `deploy/k8s/overlays/prod/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: atlas-prod

resources:
  - ../../base
  - namespace.yaml

patches:
  - path: configmap-patch.yaml
  - path: deployment-patch.yaml

images:
  - name: atlas-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: prod

labels:
  - pairs:
      environment: prod
```

---

# Why this is cleaner

Instead of doing this inside patches:

```yaml
image: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:prod
```

we do this in `kustomization.yaml`:

```yaml
images:
  - name: atlas-api
    newName: 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api
    newTag: prod
```

That gives you:

- cleaner patches
- less duplication
- easier CI/CD image substitution
- safer environment overrides

That is the more senior pattern.

---

# How to render

```bash
kubectl kustomize deploy/k8s/overlays/dev
kubectl kustomize deploy/k8s/overlays/staging
kubectl kustomize deploy/k8s/overlays/prod
```

# How to apply

```bash
kubectl apply -k deploy/k8s/overlays/dev
kubectl apply -k deploy/k8s/overlays/staging
kubectl apply -k deploy/k8s/overlays/prod
```

---

# One more senior note

For a truly production-grade setup, next step after this is:

- stop hardcoding tags like `dev`, `staging`, `prod`
- let CI update `newTag` to an immutable image tag like Git SHA
- deploy through Argo CD or pipeline promotion

Example:

```yaml
newTag: git-a1b2c3d
```
