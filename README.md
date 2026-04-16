# Valkey Platform (On-Prem)

## Overview

This repository deploys Valkey on Kubernetes using a two-layer architecture:

- Valkey Operator (controller layer)
- Valkey Cluster (CR-based workload layer)

The operator manages all runtime Kubernetes resources (StatefulSets, Services, PVCs), while the cluster chart only defines the Valkey Custom Resource.

## Repository Structure

```
valkey-platform/
├── operator-chart/     # Installs Valkey operator
├── cluster-chart/      # Deploys Valkey cluster (CR only)
└── environments/       # Environment-specific values
```

## Prerequisites

- Kubernetes cluster (1.24+ recommended)
- kubectl configured
- Helm 3+
- Namespace: `valkey`

## Important Notes

- The operator is installed from a pinned `install.yaml`
  Source:
  [https://github.com/hyperspike/valkey-operator/releases/download/v0.0.61/install.yaml](https://github.com/hyperspike/valkey-operator/releases/download/v0.0.61/install.yaml)

- Do not manually install CRDs

- Do not create StatefulSets manually

- All cluster resources are managed via the `Valkey` custom resource

## 1. Create Namespace

```bash
kubectl create namespace valkey
```

## 2. Install Valkey Operator

This installs the operator using the upstream `install.yaml` bundled inside the Helm chart.

```bash
helm install valkey-operator ./operator-chart \
  -n valkey
```

### Verify operator installation

```bash
kubectl get pods -n valkey
kubectl get crds | grep valkey
```

## 3. Install Valkey Cluster (CR)

Once the operator is running, deploy the Valkey cluster:

```bash
helm install valkey-cluster ./cluster-chart \
  -n valkey \
  -f environments/dev.yaml
```

## 4. Upgrade Operator

To upgrade the operator version:

```bash
helm upgrade valkey-operator ./operator-chart -n valkey
```

## 5. Upgrade Cluster Configuration

```bash
helm upgrade valkey-cluster ./cluster-chart \
  -n valkey \
  -f environments/prod.yaml
```

## 6. Render Kubernetes Manifests (Debug)

### Operator chart

```bash
helm template valkey-operator ./operator-chart -n valkey
```

### Cluster chart

```bash
helm template valkey-cluster ./cluster-chart -n valkey -f environments/dev.yaml
```

## 7. Verify Deployment

### Check operator deployment

```bash
kubectl get deployment -n valkey
```

### Check Valkey CR

```bash
kubectl get valkey -n valkey
```

### Check pods created by operator

```bash
kubectl get pods -n valkey
```

## 8. Connect to Valkey

### Get service

```bash
kubectl get svc -n valkey
```

### Port-forward example

```bash
kubectl port-forward svc/valkey-cluster 6379:6379 -n valkey
```

### Connect using CLI

```bash
valkey-cli -h 127.0.0.1 -p 6379
```

## 9. Test Data

Inside the CLI:

```bash
SET key1 "hello valkey"
GET key1
```

## Architecture Summary

```
Helm Chart (operator)
        ↓
install.yaml (CRDs + RBAC + Controller)
        ↓
Valkey Operator running
        ↓
Valkey CR applied (cluster-chart)
        ↓
Operator creates StatefulSets, PVCs, Services
```

## Recommended Workflow

- Use `operator-chart` only for platform setup
- Use `cluster-chart` for environments (dev/stage/prod)
- Treat the operator as an immutable infrastructure component
