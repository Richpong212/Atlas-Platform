# Atlas Platform Cluster Bootstrap

This folder contains the **Phase 2 bootstrap layer** for the Atlas Platform EKS cluster.

The purpose of this layer is to prepare the cluster **before** application workloads are deployed.

We do not want teams or services deploying directly into an unprepared cluster.  
A senior-level platform starts by defining:

- where workloads live
- what resources they can consume
- what defaults apply if developers forget to define them
- what network traffic is allowed by default
- where platform tooling like Argo CD will live

---

# Why this bootstrap exists

A Kubernetes cluster that has no structure becomes messy very quickly.

Common problems in unprepared clusters:

- workloads get deployed into `default`
- teams consume resources without limits
- pods run without requests or limits
- namespaces have no boundaries
- internal cluster traffic is too open
- platform tooling has no dedicated place to live

This bootstrap phase solves that by laying down the **baseline operating model** for the cluster.

---

# What this bootstrap creates

This folder creates:

- environment namespaces
- an Argo CD namespace
- default CPU and memory behavior for containers
- namespace-level resource caps
- baseline deny-by-default network policies
- DNS egress allowances so workloads can still resolve names

---

# File-by-file explanation

## `namespaces.yaml`

### Why it exists

This file creates the main application namespaces:

- `atlas-dev`
- `atlas-staging`
- `atlas-prod`

### What it means

We are treating namespaces as our first level of environment separation.

Instead of putting everything into one namespace, we explicitly separate environments.

That gives us:

- cleaner organization
- safer workload separation
- easier RBAC later
- easier GitOps targeting later
- clearer operational ownership

### Why labels are included

Labels make the namespaces easier to identify and select later.

For example:

- `environment=dev`
- `app.kubernetes.io/part-of=atlas-platform`

These labels are useful for policy targeting, observability, and platform consistency.

---

## `argocd-namespace.yaml`

### Why it exists

This file creates the `argocd` namespace.

### What it means

Argo CD is a platform tool, not an application workload.  
It should live in a dedicated namespace instead of being mixed with app namespaces.

This keeps:

- platform tooling separated from application workloads
- GitOps installation predictable
- future troubleshooting cleaner

### Why we create it now

Even though Argo CD is not installed yet, we define its home early so the cluster bootstrap remains intentional and repeatable.

---

## `dev-limitrange.yaml`

## `staging-limitrange.yaml`

## `prod-limitrange.yaml`

### Why they exist

These files define a `LimitRange` in each namespace.

### What a LimitRange does

A `LimitRange` sets default resource requests and limits for containers if the workload does not define them explicitly.

This matters because pods without requests and limits can create scheduling problems and unstable cluster behavior.

### What they mean

They enforce sensible defaults such as:

- default CPU request
- default memory request
- default CPU limit
- default memory limit
- minimum allowed resource settings
- maximum allowed resource settings

### Why dev, staging, and prod are separate files

Each environment may need different defaults.

For example:

- dev can have lighter defaults
- prod may require stronger minimums and higher limits

Keeping them as separate files makes the platform easier to tune per environment.

---

## `dev-resourcequota.yaml`

## `staging-resourcequota.yaml`

## `prod-resourcequota.yaml`

### Why they exist

These files define a `ResourceQuota` in each namespace.

### What a ResourceQuota does

A `ResourceQuota` limits the **total** amount of cluster resources a namespace can consume.

This is different from `LimitRange`.

- `LimitRange` controls per-container defaults and bounds
- `ResourceQuota` controls total namespace consumption

### What they mean

These files place upper bounds on things like:

- total requested CPU
- total requested memory
- total limited CPU
- total limited memory
- number of pods
- number of services
- number of configmaps
- number of secrets
- number of persistent volume claims

### Why this matters

Without quotas, one environment can grow carelessly and consume more than intended.

This is especially important when:

- multiple teams share a cluster
- dev workloads should not expand uncontrollably
- staging should remain predictable
- prod needs a defined capacity envelope

---

## `dev-default-deny.yaml`

## `staging-default-deny.yaml`

## `prod-default-deny.yaml`

### Why they exist

These files create a baseline `NetworkPolicy` that denies all ingress and egress traffic by default inside each application namespace.

### What they mean

The design principle here is:

> start from deny, then explicitly allow what is needed

Instead of allowing everything and trying to lock it down later, we define the secure baseline first.

### Why this is important

Without a deny-by-default model:

- pods may talk too freely inside the cluster
- service boundaries are weak
- lateral movement becomes easier
- platform security posture becomes unclear

### Important EKS note

These manifests represent the correct platform design, but actual enforcement on EKS depends on network policy support being enabled in the cluster networking layer.

So these files are still worth keeping in Git now, because they define the intended behavior.

---

## `dev-allow-dns.yaml`

## `staging-allow-dns.yaml`

## `prod-allow-dns.yaml`

### Why they exist

If you deny all egress traffic, pods also lose DNS access unless you explicitly allow it.

These files allow outbound DNS traffic to the `kube-system` namespace on:

- UDP 53
- TCP 53

### What they mean

They carve out the minimum exception needed for workloads to still resolve names.

This follows the same principle as before:

- deny everything first
- allow only what is necessary

### Why this matters

Without DNS:

- service discovery fails
- external lookups fail
- many applications break immediately

So DNS allowance is one of the first required exceptions after default deny.

---

## `apply-bootstrap.sh`

### Why it exists

This script makes the bootstrap repeatable.

### What it means

Instead of manually applying many YAML files one by one every time, the script provides a standard way to bootstrap the cluster in the correct order.

That helps with:

- consistency
- speed
- fewer manual mistakes
- easier onboarding for others using the repo

### Why order matters

The script applies resources in a sensible order:

1. namespaces
2. argocd namespace
3. limit ranges
4. resource quotas
5. network policies

This matches how the cluster should be prepared.

---

## `README.md` in this folder

### Why it exists

This document explains the purpose of the bootstrap layer.

### What it means

A strong repo should not only contain manifests — it should explain:

- why they exist
- what problem they solve
- how they fit together
- how to apply and verify them

This is part of making the repo public and useful to others.

---

# How the files work together

The files are not random. They build on each other.

## Step 1 — namespaces

First, we create places for workloads and platform tooling to live.

## Step 2 — resource defaults

Next, we define default requests and limits using `LimitRange`.

## Step 3 — resource caps

Then, we place aggregate caps on each namespace using `ResourceQuota`.

## Step 4 — network baseline

After that, we deny all traffic by default using `NetworkPolicy`.

## Step 5 — allow required traffic

Then we add back only what is necessary, starting with DNS.

This is a senior-level pattern:

- define structure first
- define defaults
- define boundaries
- allow exceptions intentionally

---

# How to run it

## 1. Make sure kubeconfig is pointing to the EKS cluster

Run:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name atlas-dev-eks-cluster
```

````

Then verify:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

You should see:

- the EKS context active
- worker nodes in `Ready`
- core system pods running

---

## 2. Make the script executable

```bash
chmod +x deploy/bootstrap/apply-bootstrap.sh
```

---

## 3. Run the bootstrap

```bash
./deploy/bootstrap/apply-bootstrap.sh
```

This will apply all namespace, quota, limit, and network policy files.

---

## 4. Verify the result

Run:

```bash
kubectl get ns
kubectl get limitrange -A
kubectl get resourcequota -A
kubectl get networkpolicy -A
```

You should see:

- `atlas-dev`
- `atlas-staging`
- `atlas-prod`
- `argocd`

And you should also see:

- one `LimitRange` per app namespace
- one `ResourceQuota` per app namespace
- two `NetworkPolicy` resources per app namespace

---

# How to inspect individual resources

## Inspect namespaces

```bash
kubectl get ns --show-labels
```

## Inspect a specific LimitRange

```bash
kubectl describe limitrange atlas-dev-default-limits -n atlas-dev
```

## Inspect a specific ResourceQuota

```bash
kubectl describe resourcequota atlas-dev-quota -n atlas-dev
```

## Inspect network policies

```bash
kubectl describe networkpolicy default-deny-all -n atlas-dev
kubectl describe networkpolicy allow-dns-egress -n atlas-dev
```

---

# Operational notes

## 1. Default namespace is not part of the platform model

We do not plan to deploy Atlas workloads into `default`.

Application workloads should live in:

- `atlas-dev`
- `atlas-staging`
- `atlas-prod`

---

## 2. These manifests are part of the platform contract

They define how environments are expected to behave.

This means:

- future workloads must respect namespace boundaries
- future app manifests should set explicit resources even though defaults exist
- future network access should be explicitly opened when needed

---

## 3. NetworkPolicy enforcement on EKS

These manifests define the desired security posture.

Actual enforcement depends on EKS network policy support being enabled in the cluster network layer.

So at this stage:

- the manifests are correct and worth versioning
- enforcement readiness is a later platform step

---

# Summary

This bootstrap layer gives the cluster:

- environment separation
- resource defaults
- aggregate resource control
- deny-by-default network posture
- a clean home for Argo CD

That makes the cluster ready for the next phase, where application workloads can be introduced into a prepared environment instead of an ungoverned one.

```

If you want, next I’ll give you the `docs/architecture/phase-2-bootstrap.md` file too, so the repo has both an operator README and an architecture explanation.
```
````
