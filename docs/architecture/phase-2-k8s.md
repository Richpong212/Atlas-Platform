## Phase 2 structure

```text
deploy/
├── README.md
└── bootstrap/
    ├── README.md
    ├── apply-bootstrap.sh
    ├── namespaces.yaml
    ├── argocd-namespace.yaml
    ├── dev-limitrange.yaml
    ├── staging-limitrange.yaml
    ├── prod-limitrange.yaml
    ├── dev-resourcequota.yaml
    ├── staging-resourcequota.yaml
    ├── prod-resourcequota.yaml
    ├── dev-default-deny.yaml
    ├── staging-default-deny.yaml
    ├── prod-default-deny.yaml
    ├── dev-allow-dns.yaml
    ├── staging-allow-dns.yaml
    └── prod-allow-dns.yaml
```

---

## `deploy/README.md`

````md
# Atlas Platform Deployment

This directory contains Kubernetes deployment and bootstrap resources for Atlas Platform.

## Current scope

Phase 2 bootstraps the EKS cluster with:

- environment namespaces
- namespace resource defaults via `LimitRange`
- namespace aggregate caps via `ResourceQuota`
- baseline network policies
- an `argocd` namespace for later GitOps installation

## Environments

- `atlas-dev`
- `atlas-staging`
- `atlas-prod`

## Bootstrap

```bash
./deploy/bootstrap/apply-bootstrap.sh
```
````

## Verify

```bash
kubectl get ns
kubectl get limitrange -A
kubectl get resourcequota -A
kubectl get networkpolicy -A
```

````

---

## `deploy/bootstrap/README.md`

```md
# Atlas Platform Cluster Bootstrap

This folder contains the baseline cluster resources required before application workloads are deployed.

## Why this exists

A senior-level platform does not start by throwing workloads into `default`.

We bootstrap the cluster first so that:
- environments are clearly separated
- resource defaults exist
- namespaces have bounded consumption
- security policy starts from deny-by-default
- GitOps tooling has a dedicated namespace

## Resources created

### Namespaces
- `atlas-dev`
- `atlas-staging`
- `atlas-prod`
- `argocd`

### Resource controls
- `LimitRange` in each app namespace
- `ResourceQuota` in each app namespace

### Network controls
- default deny ingress/egress in each app namespace
- DNS egress allowance in each app namespace

## Important note for EKS

These `NetworkPolicy` manifests are part of the desired platform design.

For policy enforcement on Amazon EKS, the cluster must have Amazon VPC CNI network policy support enabled and running in a supported configuration.

## Apply

```bash
./deploy/bootstrap/apply-bootstrap.sh
````

## Verify

```bash
kubectl get ns
kubectl get limitrange -A
kubectl get resourcequota -A
kubectl get networkpolicy -A
kubectl get pods -n kube-system
```

````

---

## `deploy/bootstrap/apply-bootstrap.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Applying Atlas namespaces..."
kubectl apply -f deploy/bootstrap/namespaces.yaml
kubectl apply -f deploy/bootstrap/argocd-namespace.yaml

echo "Applying LimitRanges..."
kubectl apply -f deploy/bootstrap/dev-limitrange.yaml
kubectl apply -f deploy/bootstrap/staging-limitrange.yaml
kubectl apply -f deploy/bootstrap/prod-limitrange.yaml

echo "Applying ResourceQuotas..."
kubectl apply -f deploy/bootstrap/dev-resourcequota.yaml
kubectl apply -f deploy/bootstrap/staging-resourcequota.yaml
kubectl apply -f deploy/bootstrap/prod-resourcequota.yaml

echo "Applying baseline network policies..."
kubectl apply -f deploy/bootstrap/dev-default-deny.yaml
kubectl apply -f deploy/bootstrap/staging-default-deny.yaml
kubectl apply -f deploy/bootstrap/prod-default-deny.yaml

kubectl apply -f deploy/bootstrap/dev-allow-dns.yaml
kubectl apply -f deploy/bootstrap/staging-allow-dns.yaml
kubectl apply -f deploy/bootstrap/prod-allow-dns.yaml

echo
echo "Bootstrap complete. Current state:"
kubectl get ns
echo
kubectl get limitrange -A
echo
kubectl get resourcequota -A
echo
kubectl get networkpolicy -A
````

---

## `deploy/bootstrap/namespaces.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: atlas-dev
  labels:
    environment: dev
    app.kubernetes.io/part-of: atlas-platform
    app.kubernetes.io/managed-by: kubectl
---
apiVersion: v1
kind: Namespace
metadata:
  name: atlas-staging
  labels:
    environment: staging
    app.kubernetes.io/part-of: atlas-platform
    app.kubernetes.io/managed-by: kubectl
---
apiVersion: v1
kind: Namespace
metadata:
  name: atlas-prod
  labels:
    environment: prod
    app.kubernetes.io/part-of: atlas-platform
    app.kubernetes.io/managed-by: kubectl
```

---

## `deploy/bootstrap/argocd-namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    app.kubernetes.io/name: argocd
    app.kubernetes.io/part-of: atlas-platform
    app.kubernetes.io/managed-by: kubectl
```

---

## `deploy/bootstrap/dev-limitrange.yaml`

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: atlas-dev-default-limits
  namespace: atlas-dev
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "1"
        memory: "1Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
```

---

## `deploy/bootstrap/staging-limitrange.yaml`

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: atlas-staging-default-limits
  namespace: atlas-staging
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "1"
        memory: "1Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
```

---

## `deploy/bootstrap/prod-limitrange.yaml`

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: atlas-prod-default-limits
  namespace: atlas-prod
spec:
  limits:
    - type: Container
      default:
        cpu: "1"
        memory: "1Gi"
      defaultRequest:
        cpu: "200m"
        memory: "256Mi"
      max:
        cpu: "2"
        memory: "2Gi"
      min:
        cpu: "100m"
        memory: "128Mi"
```

---

## `deploy/bootstrap/dev-resourcequota.yaml`

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: atlas-dev-quota
  namespace: atlas-dev
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "20"
    services: "10"
    configmaps: "20"
    secrets: "20"
    persistentvolumeclaims: "5"
```

---

## `deploy/bootstrap/staging-resourcequota.yaml`

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: atlas-staging-quota
  namespace: atlas-staging
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "20"
    services: "10"
    configmaps: "20"
    secrets: "20"
    persistentvolumeclaims: "5"
```

---

## `deploy/bootstrap/prod-resourcequota.yaml`

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: atlas-prod-quota
  namespace: atlas-prod
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "40"
    services: "20"
    configmaps: "30"
    secrets: "30"
    persistentvolumeclaims: "10"
```

---

## `deploy/bootstrap/dev-default-deny.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: atlas-dev
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

---

## `deploy/bootstrap/staging-default-deny.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: atlas-staging
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

---

## `deploy/bootstrap/prod-default-deny.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: atlas-prod
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

---

## `deploy/bootstrap/dev-allow-dns.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: atlas-dev
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

---

## `deploy/bootstrap/staging-allow-dns.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: atlas-staging
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

---

## `deploy/bootstrap/prod-allow-dns.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: atlas-prod
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

---

## Commands for Phase 2

Update kubeconfig and verify cluster access:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name atlas-dev-eks-cluster

kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Apply bootstrap:

```bash
chmod +x deploy/bootstrap/apply-bootstrap.sh
./deploy/bootstrap/apply-bootstrap.sh
```

Verify:

```bash
kubectl get ns
kubectl get limitrange -A
kubectl get resourcequota -A
kubectl get networkpolicy -A
```

---
