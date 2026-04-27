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
┌──────────────────────────────────────────────────────────────┐
│                    Valkey + Sentinel HA                      │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                 Sentinel (3 replicas)                   │ │
│  │  Monitors master, performs failover, manages clients    │ │
│  └─────────────────────────────────────────────────────────┘ │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────┐    ┌──────────────────┐                │
│  │     Master       │◄───│     Replica 1    │                │
│  │   (valkey-0)     │    │   (valkey-1)     │                │
│  └──────────────────┘    └──────────────────┘                │
│           │                        │                         │
│           └───────────┬────────────┘                         │
│                       ▼                                      │
│              ┌──────────────────┐                            │
│              │     Replica 2    │                            │
│              │   (valkey-2)     │                            │
│              └──────────────────┘                            │
│                                                              │
│  Services:                                                   │
│  - valkey-sentinel:26379 (Sentinel for client discovery)     │
│  - valkey-headless:6379 (StatefulSet DNS)                    │
│  - valkey:6379 (headless, for pod discovery)                 │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

### Startup

1. Pod-0 starts as master (`valkey-server` with configuration including auth and replication settings)
2. Pods 1,2 start as replicas and use the startup script to:
   - Wait for the master (valkey-0) to be ready
   - Discover the master's address via DNS (`valkey-0.valkey-headless`)
   - Configure themselves as replicas using `REPLICAOF <master-host> 6379`
3. Sentinel pods start and begin monitoring the master's health
4. All components use their respective ConfigMaps for configuration

### Failover

1. Sentinel continuously monitors the master's availability
2. When master failure is detected (after `down-after-milliseconds`):
   - Sentinels coordinate to agree on the failure
   - One sentinel is elected leader to orchestrate failover
   - The leader promotes a replica to master
   - The former master is configured as a replica when it comes back online
3. Sentinel updates its internal state with the new master information
4. Clients discover the new master by querying Sentinel:
   - `SENTINEL GETMASTER-ADDR-BY-NAME <master-name>`
   - Returns the IP and port of the current master
5. Clients then reconnect directly to the new master for operations

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

# Install with custom master name
helm install valkey ./valkey -n valkey --set sentinel.masterName=custommaster
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

# Test Sentinel connection (using default master name 'mymaster')
valkey-cli -h localhost -p 26379 sentinel get-master-addr-by-name mymaster
# To use a custom master name, replace 'mymaster' with your sentinel.masterName value

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

### Install with custom values:

```bash
helm install valkey ./valkey -n valkey -f my-values.yaml
```

### Service DNS Names

| Service             | Port  | Purpose                                       |
| ------------------- | ----- | --------------------------------------------- |
| `valkey-sentinel`   | 26379 | Sentinel for client discovery                 |
| `valkey-headless`   | 6379  | StatefulSet DNS (pod-{0,1,2}.valkey-headless) |
| `valkey` (headless) | 6379  | Pod discovery (not for direct client use)     |

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

### Client Connection

Clients must use Sentinel-aware connections to automatically discover the current master and handle failovers.
The connection requires:
- Sentinel service address: `valkey-sentinel:26379` (within same namespace) or `valkey-sentinel.<namespace>.svc.cluster.local:26379` (cross-namespace)
- Master name: value of `sentinel.masterName` (default: "mymaster")
- Password: value of `auth.password` (if auth.enabled is true)

**Using valkey-cli (manual discovery):**
```bash
# Get master address
MASTER_INFO=$(valkey-cli -h valkey-sentinel -p 26379 sentinel get-master-addr-by-name mymaster)
MASTER_HOST=$(echo $MASTER_INFO | cut -d' ' -f1)
MASTER_PORT=$(echo $MASTER_INFO | cut -d' ' -f2)

# Connect to master
valkey-cli -h $MASTER_HOST -p $MASTER_PORT -a password123 ping
```

**Using Sentinel-aware client libraries:**
Configure your client with:
- Sentinel nodes: [valkey-sentinel:26379]
- Master name: mymaster (or your custom sentinel.masterName)
- Password: password123 (if enabled)

Examples for popular clients are available in the [Valkey documentation](https://valkey.io/topics/clients).

### Check Replication Status

```bash
# Master info
kubectl exec -it valkey-0 -n valkey -- valkey-cli -h localhost -p 6379 info replication

# Replica info
kubectl exec -it valkey-1 -n valkey -- valkey-cli -h localhost -p 6379 info replication
```

### Test Failover

```bash
# Get current master (replace 'mymaster' with your sentinel.masterName if changed)
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

# Force Sentinel election (replace 'mymaster' with your sentinel.masterName if changed)
kubectl exec -it valkey-sentinel-0 -n valkey -- valkey-cli -h localhost -p 26379 sentinel failover mymaster
```