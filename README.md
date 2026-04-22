# Valkey Helm Chart

Helm chart for deploying Valkey (Redis-compatible) on Kubernetes with Sentinel-based high availability and automatic failover.

## Features

- **Replication Mode** - Master-replica replication with configurable replica count
- **Sentinel HA** - Automatic failover managed by Valkey Sentinel
- **StatefulSets** - Stable pod identity and persistent storage
- **No Cluster Mode** - Uses replication + Sentinel (not Redis Cluster hash sharding)
- **Authentication** - Password-based authentication
- **Production Ready** - Security context, probes, resource limits, PodDisruptionBudget

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Valkey + Sentinel HA                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Sentinel (3 replicas)                   │   │
│  │  Monitors master, performs failover, manages clients    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                   │
│                            ▼                                   │
│  ┌──────────────────┐    ┌──────────────────┐                 │
│  │     Master       │◄───│     Replica 1    │                 │
│  │   (valkey-0)     │    │   (valkey-1)      │                 │
│  └──────────────────┘    └──────────────────┘                 │
│           │                        │                           │
│           └───────────┬────────────┘                         │
│                       ▼                                      │
│              ┌──────────────────┐                         │
│              │     Replica 2      │                         │
│              │   (valkey-2)       │                         │
│              └──────────────────┘                         │
│                                                                 │
│  Services:                                                    │
│  - valkey-sentinel:26379 (Sentinel for client discovery)      │
│  - valkey-headless:6379 (StatefulSet DNS)                    │
│  - valkey:6379 (headless, for pod discovery)                 │
└─────────────────────────────────────────────────────────────────┘
```

## How It Works

### Startup
1. Pod-0 starts as master (`valkey-server` with config)
2. Pods 1,2 start as replicas, discovering master via Sentinel
3. Sentinel monitors master health

### Failover
1. Sentinel detects master failure (after `down-after-milliseconds`)
2. Sentinel promotes a replica to master
3. Internal state updated, clients discover new master via Sentinel

### Client Connection
Clients must use Sentinel-aware connection:
```
┌─────────────────┐
│   Application   │
│  (Sentinel      │
│   client)       │
└────────┬────────┘
         │ 1. Connect to Sentinel
         ▼
┌─────────────────┐
│ valkey-sentinel │:26379
│                 │ 2. SENTINEL GETMASTER-ADDR-BY-NAME mymaster
         │        │ 3. Returns current master IP
         ▼        │
┌─────────────────┐
│   Master        │:6379
│  (active node)  │ 4. Client connects directly
└─────────────────┘
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3+
- Valkey image that includes `valkey-sentinel` (valkey/valkey:9+)

## Installation

### 1. Render Templates (Dry Run)

```bash
helm template valkey ./valkey
```

### 2. Install the Chart

```bash
# Install with default values
helm install valkey ./valkey -n valkey --create-namespace

# Install with custom password
helm install valkey ./valkey -n valkey --set auth.password=yourpassword
```

### 3. Verify Deployment

```bash
# Check pod status
kubectl get pods -n valkey -l app.kubernetes.io/instance=valkey

# Check Sentinel status
kubectl exec -it valkey-0 -n valkey -- valkey-cli -h localhost -p 26379 info sentinel

# Check replication
kubectl exec -it valkey-0 -n valkey -- valkey-cli -h localhost -p 6379 info replication
```

### 4. Connect to Valkey

```bash
# Port forward for local access
kubectl port-forward svc/valkey-sentinel 26379:26379 -n valkey &
kubectl port-forward svc/valkey-0 6379:6379 -n valkey &

# Test Sentinel connection
valkey-cli -h localhost -p 26379 sentinel get-master-addr-by-name mymaster

# Test Valkey connection
valkey-cli -h localhost -p 6379 -a password123 ping
```

## Upgrading

```bash
# Upgrade to a new version or update values
helm upgrade valkey ./valkey -n valkey
```

## Removal

```bash
# Uninstall the release
helm uninstall valkey -n valkey

# Delete PVCs (optional - removes all data)
kubectl delete pvc -l app.kubernetes.io/instance=valkey -n valkey
```

## Configuration

| Parameter                      | Description                                    | Default              |
| ----------------------------- | -----------------------------------------------| -------------------- |
| `replication.enabled`         | Enable replication mode                        | `true`               |
| `replication.replicas`       | Number of replica pods                        | `2`                 |
| `sentinel.enabled`           | Enable Sentinel                              | `true`               |
| `sentinel.replicas`          | Number of Sentinel pods (odd number)         | `3`                 |
| `sentinel.quorum`           | Sentinel quorum for failover                  | `2`                 |
| `sentinel.failoverTimeout`    | Failover timeout (ms)                         | `10000`              |
| `sentinel.downAfterMilliseconds` | Master down detection (ms)               | `5000`               |
| `service.type`              | Service type (ClusterIP, NodePort, LoadBalancer) | `ClusterIP`        |
| `service.port`              | Valkey client port                           | `6379`               |
| `auth.enabled`              | Enable password auth                        | `true`               |
| `auth.password`             | Password                                    | `password123`        |
| `persistence.enabled`       | Enable PVC                                   | `true`              |
| `persistence.size`         | PVC size                                    | `1Gi`                |
| `persistence.storageClass`  | Storage class                               | `vsphere-db`         |
| `image.repository`         | Valkey image                                | `valkey/valkey`     |
| `image.tag`               | Valkey version                              | `9-alpine3.23`      |
| `podSecurityContext.runAsUser` | Pod user ID                                | `1000`               |
| `podSecurityContext.fsGroup`| Pod group ID                                 | `1000`               |
| `securityContext.runAsNonRoot` | Non-root execution                         | `true`               |
| `resources.limits.cpu`      | CPU limit                                   | `1`                  |
| `resources.limits.memory`   | Memory limit                                | `1Gi`                |
| `resources.requests.cpu`   | CPU request                                 | `250m`               |
| `resources.requests.memory`| Memory request                              | `512Mi`              |

### Example: Custom Values File

Create `my-values.yaml`:

```yaml
replication:
  enabled: true
  replicas: 2

sentinel:
  enabled: true
  replicas: 3
  quorum: 2
  failoverTimeout: 10000
  downAfterMilliseconds: 5000

service:
  type: ClusterIP
  port: 6379

auth:
  enabled: true
  password: mysecretpassword

persistence:
  enabled: true
  size: 10Gi
  storageClass: "vsphere-db"

resources:
  limits:
    cpu: "2"
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

Install with custom values:

```bash
helm install valkey ./valkey -n valkey -f my-values.yaml
```

## Connecting Applications

### Using Sentinel (Recommended)

To use Sentinel failover, your application must use a Sentinel-aware client:

```python
# Python example with redis-py (Sentinel)
from redis.sentinel import Sentinel

sentinel = Sentinel([('valkey-sentinel', 26379)], socket_timeout=5)
master = sentinel.master_for('mymaster', password='password123')
slave = sentinel.slave_for('mymaster', password='password123')

# Writes go to master
master.set('key', 'value')

# Reads can go to replica
slave.get('key')
```

### Using Environment Variables

```yaml
env:
  - name: VALKEY_SENTINEL_HOST
    value: "valkey-sentinel"
  - name: VALKEY_SENTINEL_PORT
    value: "26379"
  - name: VALKEY_PASSWORD
    valueFrom:
      secretKeyRef:
        name: valkey-auth
        key: password
```

### Service DNS Names

| Service                   | Port | Purpose                                      |
| ------------------------- | --- | -------------------------------------------|
| `valkey-sentinel`         | 26379 | Sentinel for client discovery              |
| `valkey-headless`         | 6379 | StatefulSet DNS (pod-{0,1,2}.valkey-headless) |
| `valkey` (headless)        | 6379 | Pod discovery (not for direct client use)    |

### Within Same Namespace

```bash
valkey-sentinel:26379
```

### From Different Namespace

```bash
valkey-sentinel.valkey.svc.cluster.local:26379
```

## Testing the Deployment

### Check Sentinel Status

```bash
# Sentinel info
kubectl exec -it valkey-0 -n valkey -- valkey-cli -h localhost -p 26379 info sentinel

# List monitored masters
kubectl exec -it valkey-0 -n valkey -- valkey-cli -h localhost -p 26379 sentinel list
```

### Check Replication Status

```bash
# Master info
kubectl exec -it valkey-0 -n valkey -- valkey-cli -h localhost -p 6379 info replication

# Replica info
kubectl exec -it valkey-1 -n valkey -- valkey-cli -h localhost -p 6379 info replication
```

### Test Failover

```bash
# Get current master
valkey-cli -h localhost -p 26379 sentinel get-master-addr-by-name mymaster

# Simulate master failure (delete master pod)
kubectl delete pod valkey-0 -n valkey

# Check new master (after failover)
valkey-cli -h localhost -p 26379 sentinel get-master-addr-by-name mymaster
```

### Test Connection

```bash
# Write to master
kubectl exec -it valkey-0 -n valkey -- valkey-cli -a password123 set testkey "Hello"

# Read from replica
kubectl exec -it valkey-1 -n valkey -- valkey-cli -h valkey-0.valkey-headless -a password123 get testkey
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod valkey-0 -n valkey

# Check pod logs
kubectl logs valkey-0 -n valkey
```

### Sentinel Not Resolving

```bash
# Verify Sentinel pods are running
kubectl get pods -n valkey -l app.kubernetes.io/component=sentinel

# Check Sentinel configuration
kubectl exec -it valkey-sentinel-0 -n valkey -- cat /etc/sentinel.conf
```

### Replication Not Working

```bash
# Check master
kubectl exec -it valkey-0 -n valkey -- valkey-cli -h localhost -p 6379 info replication

# Check replica connection
kubectl exec -it valkey-1 -n valkey -- valkey-cli -h valkey-0.valkey-headless -p 6379 ping
```

### Failover Not Triggering

```bash
# Check Sentinel logs
kubectl logs valkey-sentinel-0 -n valkey

# Force Sentinel election
kubectl exec -it valkey-sentinel-0 -n valkey -- valkey-cli -h localhost -p 26379 sentinel failover mymaster
```

## Files Structure

```
valkey/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default configuration
├── .helmignore           # Ignore patterns
├── templates/
│   ├── _helpers.tpl      # Template functions
│   ├── configmap.yaml   # Valkey configuration
│   ├── sentinel-configmap.yaml  # Sentinel configuration
│   ├── secret.yaml     # Authentication secret
│   ├── serviceaccount.yaml  # Pod service account
│   ├── service.yaml  # Client service (headless)
│   ├── service-headless.yaml  # Headless service for StatefulSet
│   ├── sentinel-service.yaml  # Sentinel service
│   ├── statefulset.yaml   # Valkey StatefulSet
│   ├── sentinel-statefulset.yaml  # Sentinel StatefulSet
│   ├── valkey-pdb.yaml    # PodDisruptionBudget for Valkey
│   ├── sentinel-pdb.yaml  # PodDisruptionBudget for Sentinel
└── README.md             # This file
```

## Security Considerations

- Passwords are stored in Kubernetes Secret (not in Pod spec)
- Pods run as non-root (UID 1000)
- Capabilities dropped, privilege escalation disabled
- Use external secrets (Vault, AWS Secrets Manager) for production passwords
- Consider network policies to restrict pod-to-pod communication