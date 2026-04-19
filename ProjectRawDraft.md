# Project Name

**Atlas Platform**

A public, production-style platform starter that shows how to build, package, deploy, and operate multiple services on AWS using:

- CloudFormation
- ECR
- EKS
- GitHub Actions
- Kustomize
- Argo CD

---

# Core Goal

Build a platform that is:

- strong enough to teach real cloud and platform concepts
- structured enough for others to clone and extend
- modular enough to grow over time
- clean enough to serve as a public showcase project

---

# What This Project Will Contain

## Infrastructure Layer

Provisioned with **CloudFormation**:

- VPC
- public/private subnets
- Internet Gateway
- NAT Gateway
- route tables
- security groups
- ECR repositories
- EKS cluster
- EKS managed node group
- IAM roles and policies
- optional ALB-related setup later

## Workload Layer

Running on **EKS**:

- frontend
- api
- auth-service
- later a worker service

## Delivery Layer

Using **GitHub Actions**:

- test
- build
- scan
- push images to ECR
- update deployment manifests

## GitOps Layer

Using **Argo CD**:

- deploy workloads to EKS
- reconcile desired state from Git
- show sync status and drift
- promote changes through environments

---

# Design Principles

These are the rules we will design around.

## 1. Build once

Each service image is built once in CI.

## 2. Promote, don’t rebuild

The same image moves through environments.

## 3. Config changes by environment

Environment differences come from config, not rebuilding images.

## 4. Git is the source of truth

Desired Kubernetes state lives in Git.

## 5. Infrastructure and workloads are separate

CloudFormation creates AWS resources.
Kubernetes and Argo CD manage applications.

## 6. Public repo quality matters

Clear structure, docs, naming, and extension points.

---

# Environment Model

We define environments clearly from the beginning.

## Local

Used for coding and quick application testing.

## Dev

First deployed environment in EKS for integration and early validation.

## Staging

Production-like environment for release validation.

## Prod

Live environment.

Inside EKS, each environment will map to its own namespace at first.

Example:

- `atlas-dev`
- `atlas-staging`
- `atlas-prod`

Later, if we want, the design can evolve into separate clusters per environment, but namespace separation is the right first step.

---

# Architecture Outline

## Application Services

### 1. API

Main backend service.

Responsibilities:

- health endpoint
- version endpoint
- business endpoints
- calls auth-service when needed

### 2. Auth Service

Separate internal service.

Responsibilities:

- token validation simulation
- auth-related endpoints
- internal-only communication

### 3. Frontend

Simple UI that calls the API.

Responsibilities:

- display app data
- demonstrate environment-based runtime config

### 4. Worker

Added later.

Responsibilities:

- background jobs
- async processing
- demonstrates non-HTTP workload pattern

---

# Repository Outline

We will use a **monorepo** first.

```text
atlas-platform/
├── apps/
│   ├── api/
│   ├── auth-service/
│   ├── frontend/
│   └── worker/
│
├── infra/
│   └── cloudformation/
│       ├── network/
│       ├── security/
│       ├── ecr/
│       ├── eks/
│       ├── iam/
│       ├── monitoring/
│       └── root/
│
├── deploy/
│   ├── base/
│   │   ├── api/
│   │   ├── auth-service/
│   │   ├── frontend/
│   │   └── worker/
│   │
│   ├── overlays/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   │
│   └── argocd/
│       ├── projects/
│       ├── applications/
│       └── bootstrap/
│
├── platform/
│   ├── ci/
│   ├── scripts/
│   ├── standards/
│   └── policies/
│
├── docs/
│   ├── architecture/
│   ├── runbooks/
│   ├── adr/
│   └── tutorials/
│
└── .github/
    └── workflows/
```

This gives us clean separation between:

- app code
- AWS infra
- Kubernetes manifests
- platform docs and rules

---

# CloudFormation Scope

CloudFormation will own AWS resources only.

## Phase 1 scope

- VPC
- subnets
- Internet Gateway
- NAT Gateway
- route tables
- security groups
- ECR repositories
- EKS cluster
- node group
- IAM roles

## Later scope

- ALB supporting resources
- CloudWatch alarms
- SNS notifications
- optional RDS if we add persistence
- optional S3 buckets
- optional Secrets Manager integration

---

# Kubernetes Scope

Kubernetes will own the application runtime.

That includes:

- Deployments
- Services
- ConfigMaps
- Secrets
- Ingress
- HPAs later
- NetworkPolicies later

We will use **Kustomize** for environment overlays.

---

# Argo CD Scope

Argo CD will own cluster reconciliation.

Meaning:

- watch Git for manifest changes
- sync to EKS
- show deployment state
- detect drift
- optionally auto-sync for dev
- likely manual approval flow for staging/prod

Important mental model:

- GitHub Actions builds images
- GitHub Actions updates Git manifests
- Argo CD syncs cluster state from Git

---

# CI/CD Outline

## Build pipeline responsibilities

For each service:

- lint
- test
- build Docker image
- scan image
- tag image with commit SHA
- push to ECR

## Delivery pipeline responsibilities

- update image tag in manifest or Kustomize overlay
- commit change to GitOps path
- Argo CD reconciles

This separates build from deployment cleanly.

---

# Versioning Strategy

We keep it simple and strong.

## Image tag format

Primary:

- full Git SHA

Optional secondary:

- semantic version later

Example:

- `atlas-api:3f9c2ab`

Rules:

- no `latest`
- no rebuilding same release for another environment
- all deployments use pinned tags

---

# Config Strategy

This is important from the start.

## Same image across all environments

We will not rebuild for dev, staging, or prod.

## Environment differences handled through:

- ConfigMaps
- Secrets
- Kustomize overlays

Examples:

- API base URL
- log level
- replica count
- feature flags

---

# Security Direction

We won’t over-engineer early, but we design with security in mind.

## Early

- private ECR repos
- IAM least privilege where practical
- non-root containers
- Kubernetes secrets separation
- image scanning in CI

## Later

- IRSA
- NetworkPolicies
- secret externalization
- policy enforcement
- admission control direction if we want

---

# Observability Direction

Not in phase 1, but in design from day one.

## Early

- health endpoint
- readiness endpoint
- structured logs
- version endpoint

## Later

- metrics
- dashboards
- alerts
- tracing direction if needed

---

# Public Repo Goals

The repo should be useful for three groups:

## Learners

They can follow phases and understand concepts.

## Builders

They can clone and extend the platform.

## Hiring managers / engineers

They can see design quality, not just random YAML.

So our docs must explain:

- why the structure exists
- how environments work
- how delivery works
- how to extend the system

---

# Build Phases

Here is the full phased outline.

## Phase 0 — Design and Standards

Define:

- architecture
- repo structure
- naming
- service boundaries
- environment rules
- delivery philosophy

## Phase 1 — CloudFormation Foundation

Build AWS infrastructure:

- VPC
- subnets
- routing
- security groups
- ECR
- EKS
- node group
- IAM roles

## Phase 2 — Bootstrap EKS Access

Set up:

- kubeconfig access
- base namespaces
- cluster verification
- Argo CD installation plan

## Phase 3 — First Service: API

Build:

- Node.js/TypeScript API
- health/version endpoints
- Dockerfile
- local run

## Phase 4 — Container Standards

Add:

- production-ready Dockerfile
- `.dockerignore`
- non-root user
- metadata labels
- image tagging rules

## Phase 5 — Kubernetes Base Manifests

Create:

- Deployment
- Service
- ConfigMap
- probes
- resource requests and limits

## Phase 6 — Environment Overlays

Create:

- dev overlay
- staging overlay
- prod overlay
- namespace-specific config

## Phase 7 — GitHub Actions Build Pipeline

Add:

- lint
- test
- build
- scan
- push to ECR

## Phase 8 — GitOps with Argo CD

Install and configure:

- Argo CD
- Application or App-of-Apps structure
- sync dev first

## Phase 9 — Auth Service

Build and deploy internal auth-service.

## Phase 10 — Frontend

Build and deploy frontend.

## Phase 11 — Promotion Flow

Refine:

- image updates by environment
- sync strategy
- promotion docs

## Phase 12 — Platform Maturity

Add:

- ingress
- network policies
- worker service
- observability basics
- runbooks
- rollback process

---

# Recommended Order for Us

To keep learning clean, I recommend this exact order:

1. Lock design
2. Build CloudFormation infrastructure
3. Verify EKS access
4. Build API service
5. Dockerize API
6. Create Kubernetes manifests
7. Add overlays
8. Add GitHub Actions
9. Install Argo CD
10. Move delivery to GitOps
11. Add auth-service
12. Add frontend
13. Add maturity features

---

# Key Decisions We’re Making Now

These are the design choices we are locking in:

## Decision 1

Use **EKS**, not local-only Kubernetes.

## Decision 2

Use **CloudFormation** for AWS infrastructure.

## Decision 3

Use **Kustomize** for manifests and overlays.

## Decision 4

Use **Argo CD**, but after the manifest structure is ready.

## Decision 5

Use a **monorepo** first.

## Decision 6

Use **namespaces per environment** initially.

## Decision 7

Use **Git SHA pinned images**.

---

# What We Should Create First

Before touching infra code, the next concrete thing is a **design doc** in the repo.

That doc should include:

- project purpose
- architecture summary
- repo structure
- AWS resources
- service map
- environment strategy
- CI/CD flow
- GitOps flow
- roadmap phases
