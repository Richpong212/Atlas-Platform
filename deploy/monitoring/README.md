# Atlas Platform Monitoring

This folder installs the monitoring stack for Atlas Platform.

## What it installs

The stack installs:

- Prometheus
- Grafana
- Alertmanager
- kube-state-metrics
- node-exporter
- default Kubernetes dashboards and rules

## Why this exists

A platform is not production-ready just because workloads run.

We need visibility into:

- pod health
- deployment status
- node usage
- CPU and memory pressure
- restart loops
- failed scheduling
- cluster-level alerts

## Install

```bash
./deploy/monitoring/install-monitoring.sh
```
