
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