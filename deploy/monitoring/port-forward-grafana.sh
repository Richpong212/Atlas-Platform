#!/usr/bin/env bash
set -euo pipefail

kubectl port-forward -n monitoring svc/atlas-monitoring-grafana 3000:80