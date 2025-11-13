# Redpanda GKE Helm Chart

Enterprise-grade Redpanda deployment for Google Kubernetes Engine (GKE) with external access via LoadBalancer services.

## Features

- **High Availability**: 3+ broker cluster with pod anti-affinity
- **Persistent Storage**: Regional SSD persistent disks with cross-zone replication
- **External Access**: Dedicated LoadBalancer per broker with DNS configuration
- **Monitoring**: Prometheus ServiceMonitor and metrics endpoints
- **Security**: RBAC, Network Policies, configurable TLS/SASL
- **Scalability**: Horizontal Pod Autoscaler support
- **Production Ready**: PodDisruptionBudget, resource limits, health probes

## Prerequisites

- Kubernetes 1.25+
- Helm 3.0+
- GKE cluster with at least 3 nodes
- Each node: 4+ CPUs, 16GB+ RAM
- DNS management for external access

## Quick Start

### 1. Add Helm Repository (if published)

```bash
# If the chart is published to a Helm repository
helm repo add redpanda-gke https://your-helm-repo.com
helm repo update
```

### 2. Install from Local Chart

```bash
# Clone the repository
git clone https://github.com/your-repo/redpanda-gke.git
cd redpanda-gke/helm/redpanda-gke

# Install with default values
helm install redpanda . --namespace redpanda --create-namespace

# Or install with custom values
helm install redpanda . \
  --namespace redpanda \
  --create-namespace \
  --values custom-values.yaml
```

### 3. Basic Installation with Custom Domain

```bash
helm install redpanda . \
  --namespace redpanda \
  --create-namespace \
  --set external.domain=mydomain.com \
  --set replicaCount=3
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Redpanda brokers | `3` |
| `image.repository` | Redpanda image repository | `redpandadata/redpanda` |
| `image.tag` | Redpanda image tag | `v23.3.5` |
| `external.enabled` | Enable external LoadBalancer access | `true` |
| `external.domain` | External domain for brokers | `example.com` |
| `storage.size` | PVC size per broker | `100Gi` |
| `storage.storageClassName` | Storage class name | `redpanda-ssd` |
| `resources.requests.cpu` | CPU request per broker | `2` |
| `resources.requests.memory` | Memory request per broker | `6Gi` |
| `monitoring.enabled` | Enable monitoring | `true` |
| `highAvailability.podDisruptionBudget.enabled` | Enable PDB | `true` |

### Full Configuration

See [values.yaml](values.yaml) for all available configuration options.

## Installation Examples

### Example 1: Production Deployment with Static IPs

```bash
# First, reserve static IPs in GCP
gcloud compute addresses create redpanda-0-ip --region=us-central1
gcloud compute addresses create redpanda-1-ip --region=us-central1
gcloud compute addresses create redpanda-2-ip --region=us-central1

# Create custom values file
cat > production-values.yaml <<EOF
external:
  enabled: true
  domain: redpanda.mycompany.com
  loadBalancer:
    staticIPs:
      enabled: true
      broker0: "redpanda-0-ip"
      broker1: "redpanda-1-ip"
      broker2: "redpanda-2-ip"

replicaCount: 3

storage:
  size: 200Gi

resources:
  requests:
    cpu: "4"
    memory: 12Gi
  limits:
    cpu: "8"
    memory: 16Gi

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
EOF

# Install
helm install redpanda . -f production-values.yaml --namespace redpanda --create-namespace
```

### Example 2: Development Deployment (Internal Only)

```bash
cat > dev-values.yaml <<EOF
external:
  enabled: false

replicaCount: 1

storage:
  size: 50Gi

resources:
  requests:
    cpu: "1"
    memory: 4Gi
  limits:
    cpu: "2"
    memory: 6Gi

highAvailability:
  podDisruptionBudget:
    enabled: false
  podAntiAffinity:
    type: soft

config:
  developerMode: true
EOF

helm install redpanda-dev . -f dev-values.yaml --namespace redpanda-dev --create-namespace
```

### Example 3: High Performance Setup

```bash
cat > high-perf-values.yaml <<EOF
replicaCount: 5

storage:
  size: 500Gi
  gke:
    type: pd-ssd

resources:
  requests:
    cpu: "8"
    memory: 24Gi
  limits:
    cpu: "16"
    memory: 32Gi

startupArgs:
  smp: 8
  memory: 20G
  reserveMemory: 10G

external:
  enabled: true
  domain: redpanda.mycompany.com
EOF

helm install redpanda-perf . -f high-perf-values.yaml --namespace redpanda --create-namespace
```

### Example 4: Enable Autoscaling

```bash
cat > autoscaling-values.yaml <<EOF
replicaCount: 3

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

resources:
  requests:
    cpu: "2"
    memory: 6Gi
  limits:
    cpu: "4"
    memory: 8Gi
EOF

helm install redpanda . -f autoscaling-values.yaml --namespace redpanda --create-namespace
```

## Post-Installation Steps

### 1. Verify Installation

```bash
# Check Helm release status
helm status redpanda -n redpanda

# Watch pods coming up
kubectl get pods -n redpanda -w

# Check cluster health
kubectl exec -n redpanda redpanda-0 -- rpk cluster health
```

### 2. Get External LoadBalancer IPs

```bash
# Get external IPs
kubectl get svc -n redpanda | grep external

# Or get specific IPs
kubectl get svc redpanda-0-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl get svc redpanda-1-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl get svc redpanda-2-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 3. Configure DNS

Create DNS A records:

```
redpanda-0.mydomain.com  →  <EXTERNAL-IP-0>
redpanda-1.mydomain.com  →  <EXTERNAL-IP-1>
redpanda-2.mydomain.com  →  <EXTERNAL-IP-2>
```

### 4. Test Connectivity

```bash
# From within cluster
kubectl run -it --rm test --image=redpandadata/redpanda:v23.3.5 --restart=Never -- \
  rpk cluster info --brokers redpanda.redpanda.svc.cluster.local:9092

# From external (after DNS configuration)
rpk cluster info --brokers redpanda-0.mydomain.com:9094,redpanda-1.mydomain.com:9094,redpanda-2.mydomain.com:9094
```

## Upgrading

### Upgrade Redpanda Version

```bash
# Upgrade to new Redpanda version
helm upgrade redpanda . \
  --namespace redpanda \
  --set image.tag=v23.3.6 \
  --reuse-values

# Monitor the rolling update
kubectl rollout status statefulset/redpanda -n redpanda
```

### Upgrade Chart Configuration

```bash
# Update with new values
helm upgrade redpanda . \
  --namespace redpanda \
  --values updated-values.yaml

# Or set specific values
helm upgrade redpanda . \
  --namespace redpanda \
  --set replicaCount=5 \
  --reuse-values
```

## Scaling

### Manual Scaling

```bash
# Scale to 5 brokers
helm upgrade redpanda . \
  --namespace redpanda \
  --set replicaCount=5 \
  --reuse-values

# Note: You'll need to create additional external LoadBalancer services
# and configure DNS for new brokers
```

### With Autoscaling

If HPA is enabled, scaling happens automatically based on CPU/memory utilization.

## Uninstalling

```bash
# Uninstall the release
helm uninstall redpanda -n redpanda

# Delete PVCs (WARNING: This deletes all data)
kubectl delete pvc -n redpanda --all

# Delete namespace
kubectl delete namespace redpanda
```

## Monitoring

### Accessing Metrics

```bash
# Port-forward metrics endpoint
kubectl port-forward -n redpanda svc/redpanda-metrics 9644:9644

# View metrics
curl http://localhost:9644/metrics
```

### With Prometheus Operator

If you have Prometheus Operator installed, metrics will be automatically scraped via the ServiceMonitor.

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n redpanda
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod redpanda-0 -n redpanda

# Check events
kubectl get events -n redpanda --sort-by='.lastTimestamp'

# Check logs
kubectl logs redpanda-0 -n redpanda
```

### External LoadBalancer Not Getting IP

```bash
# Check service
kubectl describe svc redpanda-0-external -n redpanda

# Check GKE load balancers
gcloud compute forwarding-rules list
```

### Cluster Not Forming

```bash
# Check connectivity between pods
kubectl exec -n redpanda redpanda-0 -- nc -zv redpanda-1.redpanda-internal.redpanda.svc.cluster.local 33145

# Check seed server configuration
kubectl exec -n redpanda redpanda-1 -- cat /etc/redpanda/redpanda.yaml | grep seed_servers
```

### DNS Issues

```bash
# Test DNS resolution
kubectl exec -n redpanda redpanda-0 -- nslookup redpanda-1.redpanda-internal.redpanda.svc.cluster.local

# Check external DNS
nslookup redpanda-0.mydomain.com
```

## Advanced Configuration

### Custom Redpanda Configuration

You can mount additional configuration by modifying the ConfigMap template or using init containers.

### TLS/SSL Configuration

To enable TLS (not included by default):

1. Create TLS secrets with certificates
2. Mount secrets in StatefulSet
3. Update Redpanda configuration to enable TLS
4. Update service ports

### SASL Authentication

To enable SASL authentication:

1. Create secrets with credentials
2. Update ConfigMap with SASL configuration
3. Update listeners to require authentication

## Values Schema

For a complete reference of all values, see the [values.yaml](values.yaml) file with inline documentation.

## Contributing

Contributions are welcome! Please:

1. Test changes locally
2. Update documentation
3. Submit pull requests with clear descriptions

## License

This Helm chart is provided as-is for deploying Redpanda on GKE.

## Support

- [Redpanda Documentation](https://docs.redpanda.com/)
- [Redpanda Community Slack](https://redpanda.com/slack)
- [GitHub Issues](https://github.com/your-repo/redpanda-gke/issues)
