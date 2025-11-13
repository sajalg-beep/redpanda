# Enterprise-Grade Redpanda on GKE with External Access

This repository contains production-ready configurations for deploying Redpanda on Google Kubernetes Engine (GKE) with external LoadBalancer services.

## Deployment Options

This repository provides **two deployment methods**:

1. **Helm Chart (Recommended)** - Located in `helm/redpanda-gke/`
   - Fully parameterized and customizable
   - Easy upgrades and rollbacks
   - Pre-configured values files for different environments
   - See [HELM.md](HELM.md) for detailed instructions

2. **Raw Kubernetes Manifests** - Located in `k8s/base/`
   - Direct kubectl deployment
   - Full control over resources
   - See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions

### Quick Start with Helm (Recommended)

```bash
# Install with Helm
helm install redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --create-namespace \
  --set external.domain=yourdomain.com

# See HELM.md for complete documentation
```

### Quick Start with kubectl

```bash
# Deploy with kubectl
kubectl apply -f k8s/base/

# See DEPLOYMENT.md for complete documentation
```

## Architecture Overview

- **3 Redpanda brokers** deployed as a StatefulSet with anti-affinity rules
- **Regional SSD persistent disks** for data persistence (100GB per broker)
- **Internal services** for intra-cluster communication
- **External LoadBalancer services** for each broker (external client access)
- **High availability** with PodDisruptionBudget
- **Monitoring** with Prometheus ServiceMonitor
- **Network policies** for security

## Prerequisites

1. **GKE Cluster** (recommended: GKE Standard or Autopilot)
   - Kubernetes version: 1.25+
   - Node pool with at least 3 nodes (for anti-affinity)
   - Each node should have: 4+ CPUs, 16GB+ RAM

2. **kubectl** configured to access your GKE cluster

3. **DNS Management** (for external access)
   - Ability to create DNS A records pointing to LoadBalancer IPs
   - Example domains used: `redpanda-0.example.com`, `redpanda-1.example.com`, `redpanda-2.example.com`

4. **Optional: Prometheus Operator** (for monitoring with ServiceMonitor)

## Quick Start

### 1. Configure External Domain Names

Before deployment, update the external advertised addresses in `k8s/base/04-statefulset.yaml`:

```yaml
# Line ~80 in the init container
rpk redpanda config set redpanda.advertised_kafka_api[1].address redpanda-${ORDINAL}.example.com
```

Replace `example.com` with your actual domain.

### 2. Deploy to GKE

```bash
# Apply all manifests
kubectl apply -f k8s/base/

# Verify namespace creation
kubectl get namespace redpanda

# Watch deployment progress
kubectl get pods -n redpanda -w
```

### 3. Get External LoadBalancer IPs

```bash
# Get external IPs for all brokers
kubectl get svc -n redpanda | grep external

# Example output:
# redpanda-0-external   LoadBalancer   10.x.x.x   34.x.x.x   9094:31234/TCP   2m
# redpanda-1-external   LoadBalancer   10.x.x.x   35.x.x.x   9094:31235/TCP   2m
# redpanda-2-external   LoadBalancer   10.x.x.x   36.x.x.x   9094:31236/TCP   2m
```

### 4. Configure DNS

Create A records in your DNS provider:

```
redpanda-0.example.com  →  34.x.x.x
redpanda-1.example.com  →  35.x.x.x
redpanda-2.example.com  →  36.x.x.x
```

### 5. Verify Cluster Health

```bash
# Check cluster status
kubectl exec -n redpanda redpanda-0 -- rpk cluster info

# Check cluster health
kubectl exec -n redpanda redpanda-0 -- rpk cluster health
```

## Detailed Deployment Guide

### Component Overview

| File | Purpose |
|------|---------|
| `00-namespace.yaml` | Creates the `redpanda` namespace |
| `01-storage-class.yaml` | GKE SSD storage class with regional PDs |
| `02-serviceaccount.yaml` | RBAC configuration |
| `03-configmap.yaml` | Redpanda configuration |
| `04-statefulset.yaml` | Main Redpanda deployment |
| `05-service-internal.yaml` | Internal ClusterIP services |
| `06-service-external.yaml` | External LoadBalancer services |
| `07-poddisruptionbudget.yaml` | High availability configuration |
| `08-servicemonitor.yaml` | Prometheus monitoring |
| `09-network-policy.yaml` | Network security policies |
| `10-hpa.yaml` | Horizontal Pod Autoscaler (optional) |

### Storage Configuration

The deployment uses regional SSD persistent disks:

- **Type**: `pd-ssd` (high-performance SSD)
- **Replication**: `regional-pd` (replicated across zones)
- **Size**: 100GB per broker (adjustable)
- **Reclaim Policy**: Retain (data preserved on deletion)

To adjust storage size, edit `k8s/base/04-statefulset.yaml`:

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      resources:
        requests:
          storage: 100Gi  # Change this value
```

### Resource Configuration

Default resource allocation per broker:

- **CPU Request**: 2 cores
- **CPU Limit**: 4 cores
- **Memory Request**: 6GB
- **Memory Limit**: 8GB

Adjust in `k8s/base/04-statefulset.yaml` based on your workload.

### High Availability Features

1. **Anti-Affinity Rules**: Pods spread across different nodes and zones
2. **PodDisruptionBudget**: Ensures at least 2 brokers remain available during maintenance
3. **Regional Persistent Disks**: Data replicated across zones
4. **Health Probes**: Automatic pod restart on failures

### Scaling

To scale the cluster:

```bash
# Scale to 5 brokers
kubectl scale statefulset redpanda -n redpanda --replicas=5

# Create additional external LoadBalancer services for new brokers
# Copy and modify 06-service-external.yaml for brokers 3, 4, etc.
```

**Important**: When scaling, you must:
1. Create new external LoadBalancer services
2. Configure DNS for new broker external addresses
3. Update the StatefulSet init container if using different domain patterns

## External Access Configuration

### Connection from External Clients

Use the following bootstrap servers:

```
redpanda-0.example.com:9094
redpanda-1.example.com:9094
redpanda-2.example.com:9094
```

Example with `rpk`:

```bash
rpk topic list --brokers redpanda-0.example.com:9094,redpanda-1.example.com:9094,redpanda-2.example.com:9094
```

### Using Static IPs (Optional)

To reserve static IPs in GKE:

```bash
# Reserve static IPs
gcloud compute addresses create redpanda-0-ip --region=us-central1
gcloud compute addresses create redpanda-1-ip --region=us-central1
gcloud compute addresses create redpanda-2-ip --region=us-central1

# Get the addresses
gcloud compute addresses describe redpanda-0-ip --region=us-central1 --format="get(address)"
```

Then uncomment and update in `06-service-external.yaml`:

```yaml
annotations:
  networking.gke.io/load-balancer-ip-addresses: "redpanda-0-ip"
```

## Internal Access Configuration

### Connection from Within GKE Cluster

For applications running in the same cluster, use the internal service:

```
redpanda.redpanda.svc.cluster.local:9092
```

Or individual broker DNS:

```
redpanda-0.redpanda-internal.redpanda.svc.cluster.local:9092
redpanda-1.redpanda-internal.redpanda.svc.cluster.local:9092
redpanda-2.redpanda-internal.redpanda.svc.cluster.local:9092
```

## Monitoring

### Prometheus Integration

If you have Prometheus Operator installed, the ServiceMonitor will automatically configure scraping:

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n redpanda

# View metrics endpoint
kubectl port-forward -n redpanda svc/redpanda-metrics 9644:9644
# Visit http://localhost:9644/metrics
```

### Key Metrics to Monitor

- `redpanda_kafka_request_latency_seconds`
- `redpanda_storage_disk_free_bytes`
- `redpanda_cluster_brokers`
- `redpanda_kafka_request_bytes_total`
- `redpanda_rpc_request_errors_total`

### Grafana Dashboards

Import official Redpanda Grafana dashboards:
- Dashboard ID: 17132 (Redpanda Ops Dashboard)

## Operations

### Accessing Redpanda Admin

```bash
# Port-forward admin API
kubectl port-forward -n redpanda svc/redpanda 9644:9644

# Access admin API
curl http://localhost:9644/v1/cluster/health_overview
```

### Using rpk CLI

```bash
# Execute rpk commands inside a pod
kubectl exec -n redpanda redpanda-0 -- rpk cluster info

# Create a topic
kubectl exec -n redpanda redpanda-0 -- rpk topic create test-topic -p 3 -r 3

# List topics
kubectl exec -n redpanda redpanda-0 -- rpk topic list

# Produce messages
kubectl exec -n redpanda redpanda-0 -- rpk topic produce test-topic

# Consume messages
kubectl exec -n redpanda redpanda-0 -- rpk topic consume test-topic
```

### Logs

```bash
# View logs for a specific broker
kubectl logs -n redpanda redpanda-0 -f

# View logs from all brokers
kubectl logs -n redpanda -l app=redpanda --tail=100
```

### Backup and Recovery

```bash
# Backup topic data (using rpk)
kubectl exec -n redpanda redpanda-0 -- rpk topic consume my-topic --offset start > backup.txt

# Backup configuration
kubectl get configmap redpanda-config -n redpanda -o yaml > config-backup.yaml
```

### Upgrading Redpanda

```bash
# Update image version in 04-statefulset.yaml
# Then apply the change
kubectl apply -f k8s/base/04-statefulset.yaml

# Monitor the rolling update
kubectl rollout status statefulset/redpanda -n redpanda
```

## Security Considerations

### Network Policies

Network policies are included to restrict traffic. Modify `09-network-policy.yaml` to match your security requirements.

### TLS/SSL Configuration

For production, enable TLS:

1. Create TLS certificates (use cert-manager or your PKI)
2. Store certificates in Kubernetes secrets
3. Update ConfigMap to enable TLS
4. Mount certificates in StatefulSet

Example TLS configuration addition to ConfigMap:

```yaml
kafka_api_tls:
  - name: external
    enabled: true
    cert_file: /etc/tls/tls.crt
    key_file: /etc/tls/tls.key
```

### Authentication

For SASL authentication, update the ConfigMap:

```yaml
kafka_api:
  - name: external
    authentication_method: sasl
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod -n redpanda redpanda-0

# Check events
kubectl get events -n redpanda --sort-by='.lastTimestamp'

# Check storage
kubectl get pvc -n redpanda
```

### External LoadBalancer Not Getting IP

```bash
# Check service status
kubectl describe svc -n redpanda redpanda-0-external

# Check GKE load balancer creation
gcloud compute forwarding-rules list
```

### Cluster Not Forming

```bash
# Check seed server configuration
kubectl exec -n redpanda redpanda-0 -- cat /etc/redpanda/redpanda.yaml | grep seed_servers

# Check network connectivity between pods
kubectl exec -n redpanda redpanda-0 -- nc -zv redpanda-1.redpanda-internal.redpanda.svc.cluster.local 33145
```

### DNS Resolution Issues

```bash
# Test DNS from within a pod
kubectl exec -n redpanda redpanda-0 -- nslookup redpanda-1.redpanda-internal.redpanda.svc.cluster.local

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns
```

## Cost Optimization

- Use **Spot VMs** for non-critical environments
- Adjust **storage size** based on retention requirements
- Enable **storage autoscaling** for PVCs
- Use **preemptible nodes** for development clusters
- Consider **GKE Autopilot** for automatic resource optimization

## Production Checklist

- [ ] DNS records configured for all external LoadBalancers
- [ ] Static IPs reserved (optional)
- [ ] TLS/SSL enabled and certificates valid
- [ ] SASL authentication configured
- [ ] Monitoring and alerting configured
- [ ] Backup strategy implemented
- [ ] Resource limits tested under load
- [ ] Disaster recovery plan documented
- [ ] Network policies reviewed
- [ ] Access controls (RBAC) audited

## Support and Resources

- [Redpanda Documentation](https://docs.redpanda.com/)
- [Redpanda Kubernetes Guide](https://docs.redpanda.com/docs/deploy/deployment-option/self-hosted/kubernetes/)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Redpanda Community Slack](https://redpanda.com/slack)

## License

This configuration is provided as-is for enterprise deployment of Redpanda on GKE.

## Contributing

To modify this deployment:

1. Update the relevant YAML files in `k8s/base/`
2. Test changes in a development cluster
3. Document any configuration changes in this README
4. Commit changes with clear descriptions

---

**Note**: Replace `example.com` with your actual domain throughout all configurations before deploying to production.
