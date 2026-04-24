#!/usr/bin/env bash
set -euo pipefail

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring

helm upgrade --install atlas-monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values deploy/monitoring/values.yaml

kubectl get pods -n monitoring