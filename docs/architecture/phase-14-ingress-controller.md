Right now you are using `kubectl port-forward`, which is fine for testing, but not how a real platform should expose traffic.

We want this shape:

```text
internet → ingress → atlas-frontend
atlas-frontend → atlas-api
atlas-api → auth-service
```

That means:

- only the frontend is exposed externally
- API stays internal
- auth-service stays internal

That is the correct boundary.

# What this phase adds

We will add:

- an ingress controller
- an Ingress resource for `atlas-frontend`
- optional host-based routing
- a cleaner external entry point

Because you are on EKS, there are two common paths:

- **NGINX Ingress Controller**
- **AWS Load Balancer Controller**

For learning and speed, the better next step is:

## Use NGINX Ingress Controller first

Why:

- simpler to understand
- faster to install
- good for learning ingress concepts
- no extra AWS controller/IAM complexity right away

Later, if you want platform maturity on AWS-native ingress, we can move to ALB.

# Phase 14 goal

By the end of this phase, you should be able to access the frontend through an ingress endpoint instead of port-forward.

# Step 1 — install ingress-nginx

Apply the official manifest:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

Verify:

```bash
kubectl get pods -n ingress-nginx
```

Wait until they are running.

Also check the service:

```bash
kubectl get svc -n ingress-nginx
```

You should see a `LoadBalancer` service for the controller. On EKS, Kubernetes will provision an external AWS load balancer for that service.

# Step 2 — wait for external address

Run:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Look at the `EXTERNAL-IP` field.

At first it may show:

```text
<pending>
```

Wait until it becomes a hostname or address.

# Step 3 — create frontend ingress

Create this file:

## `deploy/k8s/frontend/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: atlas-frontend-ingress
  namespace: atlas-dev
  labels:
    app.kubernetes.io/name: atlas-frontend
    app.kubernetes.io/part-of: atlas-platform
spec:
  ingressClassName: nginx
  rules:
    - host: atlas-dev.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: atlas-frontend
                port:
                  number: 80
```

This routes all external traffic to the frontend service.

# Step 4 — apply ingress

```bash
kubectl apply -f deploy/k8s/frontend/ingress.yaml
```

Verify:

```bash
kubectl get ingress -n atlas-dev
kubectl describe ingress atlas-frontend-ingress -n atlas-dev
```

# Step 5 — test it

If you are not using a real DNS name yet, use the load balancer hostname and your local `/etc/hosts` later if needed.

First get the ingress controller external hostname:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o wide
```

Then test directly with curl using the host header:

```bash
curl -H "Host: atlas-dev.local" http://<EXTERNAL-HOSTNAME>/
```

That should return your frontend HTML.

If you want to test in the browser, add an entry in `/etc/hosts` after resolving the load balancer IP/hostname path you prefer, but curl with `Host` header is enough for now.

# Why this works

The flow is:

1. user hits ingress controller
2. ingress controller reads Ingress resource
3. request with host `atlas-dev.local` goes to `atlas-frontend`
4. frontend proxies `/api/` to `atlas-api`
5. API calls `auth-service`

So now the traffic model is clean.

# What stays internal

These should **not** have ingress resources:

- `atlas-api`
- `atlas-auth-service`

They remain `ClusterIP`.

That is important.

# Recommended repo addition

Your frontend folder should now contain:

```text
deploy/k8s/frontend/
├── deployment.yaml
├── service.yaml
└── ingress.yaml
```

# Important note on network policies

If your network policies become enforced later, you will need to explicitly allow:

- ingress controller to frontend
- frontend to API
- API to auth-service
- DNS egress

Right now, we laid down the manifests earlier, but enforcement depends on cluster network policy support.

# Verification checklist

Run these:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingress -n atlas-dev
kubectl get svc -n atlas-dev
kubectl get pods -n atlas-dev
```

Then test:

```bash
curl -H "Host: atlas-dev.local" http://<INGRESS-EXTERNAL-HOSTNAME>/
```

# What this phase gives you

Now you have:

- proper external entry point
- frontend exposed publicly
- API/internal services still private
- cleaner traffic architecture
- a real ingress layer in front of the platform

# Next phase

The next strong phase after this is:

## Phase 15 — Observability + Rollback + Operational Runbooks
