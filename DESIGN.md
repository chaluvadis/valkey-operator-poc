The Valkey chart in the `valkey` directory is ** configured for Valkey Sentinel-based High Availability (HA)**

### Chart Architecture (Valkey Sentinel HA)
1. **Core Components**:
   - **Valkey StatefulSet**: Runs 1 master + N replicas (default: 2 replicas → 3 pods total). 
   - **Sentinel StatefulSet**: Runs 3 Sentinel instances for monitoring and automatic failover.
   - **Services**:
     - `valkey-headless` (ClusterIP=None): Enables DNS-based pod discovery for StatefulSet.
     - `valkey` (NodePort): *Not recommended for client use* (load-balances across all Valkey pods; writes fail on replicas).
     - `valkey-sentinel` (NodePort): Primary client access point to query Sentinel for master address.
     - `valkey-sentinel-headless` (ClusterIP=None): For Sentinel StatefulSet DNS.
   - **Configuration**:
     - Valkey ConfigMap: Sets `requirepass`, `masterauth`, and replication-related settings.
     - Sentinel ConfigMap: Dynamically generated with `sentinel monitor`, `down-after-milliseconds`, `failover-timeout`, and auth settings (if enabled).
   - **Startup Script**: 
     - For non-ordinal-0 pods (replicas): Waits for master (pod-0) to be ready, then runs `replicaof <master-host> 6379`.
     - Ensures replicas discover and replicate from the master via Sentinel-managed topology.

2. **Failover Workflow**:
   - Sentinel detects master failure (after `down-after-milliseconds`).
   - Promotes a replica to master.
   - Updates internal state; clients re-query Sentinel via `SENTINEL GETMASTER-ADDR-BY-NAME <master-name>` to get new master address.

3. **Client Connection Pattern**:
   ```
   Client → [Connect to Sentinel:26379] 
            → [SENTINEL GETMASTER-ADDR-BY-NAME <master-name>] 
            → [Returns current master IP:port] 
            → [Direct connection to Valkey master:6379]
   ```