## set up valkey test pod.

```
    kubectl run valkey-test --rm -it --restart=Never \
    --image=valkey/valkey:latest \
    --command -- bash
```

valkey-cli -h valkey-sentinel.valkey-dev.svc.cluster.local -p 26379 PING
PONG

## Sentinel masters

valkey-cli -h valkey-sentinel.valkey-dev.svc.cluster.local -p 26379 SENTINEL masters

1.  1. "name"
    2. "mymaster"

## Master addres

valkey-cli -h valkey-sentinel.valkey-dev.svc.cluster.local -p 26379 SENTINEL get-master-addr-by-name mymaster

1. "valkey-0.valkey-headless.valkey-dev.svc.cluster.local"
2. "6379"

## Master Sentinels

root@valkey-test:/data# valkey-cli -h valkey-sentinel.valkey-dev.svc.cluster.local -p 26379 SENTINEL sentinels mymaster

1.  1. "name"
    2. "043bc7310dc5609cfab88b5f1258d7a8f8b7c89c"
    3. "ip"
   
## Sentinel Slave

 valkey-cli -h valkey-sentinel.valkey-dev.svc.cluster.local -p 26379 SENTINEL slaves mymaster

1.  1. "name"
    2. "10.10.100.108:6379"
    3. "ip"
   