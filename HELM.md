# Deploying Redpanda on GKE with Helm

This guide provides comprehensive instructions for deploying Redpanda on Google Kubernetes Engine using Helm.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Installation Methods](#installation-methods)
- [Configuration](#configuration)
- [Post-Installation](#post-installation)
- [Operations](#operations)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### 1. Required Tools

```bash
# Helm 3.x
helm version

# kubectl
kubectl version --client

# gcloud CLI
gcloud version
```

### 2. GKE Cluster

Create a GKE cluster if you don't have one:

```bash
# Set variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export CLUSTER_NAME="redpanda-cluster"

# Create cluster
gcloud container clusters create $CLUSTER_NAME \
  --project=$PROJECT_ID \
  --region=$REGION \
  --num-nodes=1 \
  --min-nodes=3 \
  --max-nodes=6 \
  --enable-autoscaling \
  --machine-type=n2-standard-4 \
  --disk-type=pd-ssd \
  --disk-size=100 \
  --enable-autorepair \
  --enable-autoupgrade \
  --enable-ip-alias

# Get credentials
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION
```

## Quick Start

### Option 1: Default Installation

```bash
# Navigate to the chart directory
cd helm/redpanda-gke

# Install with defaults
helm install redpanda . --namespace redpanda --create-namespace

# Watch deployment
kubectl get pods -n redpanda -w
```

### Option 2: Production Installation

```bash
# Edit the domain in values-production.yaml
sed -i 's/example.com/yourdomain.com/g' values-production.yaml

# Install with production values
helm install redpanda . \
  --namespace redpanda \
  --create-namespace \
  --values values-production.yaml

# Monitor deployment
kubectl get pods -n redpanda -w
```

### Option 3: Quick Install with CLI Override

```bash
helm install redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --create-namespace \
  --set external.domain=yourdomain.com \
  --set replicaCount=3 \
  --set storage.size=200Gi
```

## Installation Methods

### Development Environment

For local development or testing:

```bash
helm install redpanda-dev ./helm/redpanda-gke \
  --namespace redpanda-dev \
  --create-namespace \
  --values ./helm/redpanda-gke/values-development.yaml
```

**Features:**
- Single broker
- Internal access only
- Minimal resources
- Developer mode enabled

### Production Environment

For production workloads:

```bash
# First, reserve static IPs (recommended)
gcloud compute addresses create redpanda-0-ip --region=$REGION
gcloud compute addresses create redpanda-1-ip --region=$REGION
gcloud compute addresses create redpanda-2-ip --region=$REGION

# Install
helm install redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --create-namespace \
  --values ./helm/redpanda-gke/values-production.yaml \
  --set external.domain=redpanda.yourdomain.com \
  --set external.loadBalancer.staticIPs.enabled=true \
  --set external.loadBalancer.staticIPs.broker0=redpanda-0-ip \
  --set external.loadBalancer.staticIPs.broker1=redpanda-1-ip \
  --set external.loadBalancer.staticIPs.broker2=redpanda-2-ip
```

**Features:**
- 3+ brokers with HA
- External LoadBalancer access
- Production-grade resources
- Monitoring enabled
- Network policies
- PodDisruptionBudget

### High-Performance Environment

For high-throughput workloads:

```bash
helm install redpanda-perf ./helm/redpanda-gke \
  --namespace redpanda \
  --create-namespace \
  --values ./helm/redpanda-gke/values-high-performance.yaml \
  --set external.domain=redpanda.yourdomain.com
```

**Features:**
- 5+ brokers
- Maximum resources (8+ CPU, 24GB+ RAM per broker)
- 500GB storage per broker
- Autoscaling enabled
- Optimized for throughput

## Configuration

### Key Configuration Options

#### Broker Count

```bash
helm install redpanda ./helm/redpanda-gke \
  --set replicaCount=5 \
  --namespace redpanda \
  --create-namespace
```

#### External Domain

```bash
helm install redpanda ./helm/redpanda-gke \
  --set external.enabled=true \
  --set external.domain=redpanda.mycompany.com \
  --namespace redpanda \
  --create-namespace
```

#### Storage Configuration

```bash
helm install redpanda ./helm/redpanda-gke \
  --set storage.size=500Gi \
  --set storage.gke.type=pd-ssd \
  --namespace redpanda \
  --create-namespace
```

#### Resource Allocation

```bash
helm install redpanda ./helm/redpanda-gke \
  --set resources.requests.cpu=4 \
  --set resources.requests.memory=12Gi \
  --set resources.limits.cpu=8 \
  --set resources.limits.memory=16Gi \
  --namespace redpanda \
  --create-namespace
```

#### Custom Values File

Create `my-values.yaml`:

```yaml
replicaCount: 3

external:
  enabled: true
  domain: redpanda.mycompany.com

storage:
  size: 200Gi

resources:
  requests:
    cpu: "4"
    memory: 12Gi

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
```

Install with custom values:

```bash
helm install redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --create-namespace \
  --values my-values.yaml
```

## Post-Installation

### 1. Verify Deployment

```bash
# Check Helm release
helm status redpanda -n redpanda

# List all resources
helm get manifest redpanda -n redpanda

# Check pods
kubectl get pods -n redpanda

# Check services
kubectl get svc -n redpanda

# Check PVCs
kubectl get pvc -n redpanda
```

### 2. Get External LoadBalancer IPs

```bash
# Wait for external IPs to be assigned
kubectl get svc -n redpanda -w | grep external

# Get specific IPs
export IP_0=$(kubectl get svc redpanda-0-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export IP_1=$(kubectl get svc redpanda-1-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export IP_2=$(kubectl get svc redpanda-2-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Broker 0: $IP_0"
echo "Broker 1: $IP_1"
echo "Broker 2: $IP_2"
```

### 3. Configure DNS

Using Cloud DNS:

```bash
# Create DNS zone (if not exists)
gcloud dns managed-zones create redpanda-zone \
  --dns-name="yourdomain.com." \
  --description="Redpanda DNS zone"

# Add A records
gcloud dns record-sets transaction start --zone=redpanda-zone

gcloud dns record-sets transaction add $IP_0 \
  --name=redpanda-0.yourdomain.com. \
  --ttl=300 \
  --type=A \
  --zone=redpanda-zone

gcloud dns record-sets transaction add $IP_1 \
  --name=redpanda-1.yourdomain.com. \
  --ttl=300 \
  --type=A \
  --zone=redpanda-zone

gcloud dns record-sets transaction add $IP_2 \
  --name=redpanda-2.yourdomain.com. \
  --ttl=300 \
  --type=A \
  --zone=redpanda-zone

gcloud dns record-sets transaction execute --zone=redpanda-zone
```

### 4. Test Cluster

```bash
# Check cluster health
kubectl exec -n redpanda redpanda-0 -- rpk cluster health

# Check cluster info
kubectl exec -n redpanda redpanda-0 -- rpk cluster info

# Create test topic
kubectl exec -n redpanda redpanda-0 -- rpk topic create test-topic -p 3 -r 3

# List topics
kubectl exec -n redpanda redpanda-0 -- rpk topic list
```

### 5. Test External Connectivity

```bash
# Test from your local machine (after DNS propagation)
rpk cluster info --brokers \
  redpanda-0.yourdomain.com:9094,\
  redpanda-1.yourdomain.com:9094,\
  redpanda-2.yourdomain.com:9094
```

## Operations

### View Release Information

```bash
# List all Helm releases
helm list -n redpanda

# Get release status
helm status redpanda -n redpanda

# Get release values
helm get values redpanda -n redpanda

# Get all values (including defaults)
helm get values redpanda -n redpanda --all

# Get manifest
helm get manifest redpanda -n redpanda
```

### Modify Configuration

```bash
# Update specific values
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --set replicaCount=5 \
  --reuse-values

# Update with new values file
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --values new-values.yaml

# Update and wait for rollout
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --values new-values.yaml \
  --wait \
  --timeout 10m
```

### Scaling

```bash
# Scale up
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --set replicaCount=5 \
  --reuse-values

# Monitor scaling
kubectl get pods -n redpanda -w

# Note: For external access, you'll need to:
# 1. Create additional LoadBalancer services for new brokers
# 2. Configure DNS for new broker addresses
```

### Monitoring

```bash
# Port-forward to metrics endpoint
kubectl port-forward -n redpanda svc/redpanda-metrics 9644:9644

# View metrics
curl http://localhost:9644/metrics

# Check ServiceMonitor (if Prometheus Operator installed)
kubectl get servicemonitor -n redpanda
```

## Upgrading

### Upgrade Redpanda Version

```bash
# Upgrade to new Redpanda version
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --set image.tag=v23.3.6 \
  --reuse-values

# Monitor the rolling update
kubectl rollout status statefulset/redpanda -n redpanda

# Verify cluster health after upgrade
kubectl exec -n redpanda redpanda-0 -- rpk cluster health
```

### Upgrade Chart Version

```bash
# Pull latest chart changes
git pull origin main

# Upgrade with new chart
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --reuse-values

# Or specify new values
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --values updated-values.yaml
```

### Rollback

```bash
# View release history
helm history redpanda -n redpanda

# Rollback to previous version
helm rollback redpanda -n redpanda

# Rollback to specific revision
helm rollback redpanda 2 -n redpanda
```

## Uninstalling

### Complete Removal

```bash
# Uninstall Helm release
helm uninstall redpanda -n redpanda

# Delete PVCs (WARNING: This deletes all data)
kubectl delete pvc -n redpanda --all

# Delete namespace
kubectl delete namespace redpanda

# Release static IPs (if used)
gcloud compute addresses delete redpanda-0-ip --region=$REGION
gcloud compute addresses delete redpanda-1-ip --region=$REGION
gcloud compute addresses delete redpanda-2-ip --region=$REGION
```

### Preserve Data

```bash
# Uninstall but keep PVCs
helm uninstall redpanda -n redpanda

# PVCs remain and can be reused in future installations
kubectl get pvc -n redpanda
```

## Troubleshooting

### Chart Validation

```bash
# Dry-run to check what will be created
helm install redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --dry-run \
  --debug

# Template locally
helm template redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --values values-production.yaml
```

### Common Issues

#### Pods Not Starting

```bash
# Check pod events
kubectl describe pod redpanda-0 -n redpanda

# Check logs
kubectl logs redpanda-0 -n redpanda

# Check init container logs
kubectl logs redpanda-0 -n redpanda -c redpanda-configurator
```

#### LoadBalancer IP Not Assigned

```bash
# Check service
kubectl describe svc redpanda-0-external -n redpanda

# Check events
kubectl get events -n redpanda --sort-by='.lastTimestamp'

# Verify GKE can create load balancers
gcloud compute forwarding-rules list
```

#### Helm Upgrade Fails

```bash
# View release history
helm history redpanda -n redpanda

# Rollback to previous working version
helm rollback redpanda -n redpanda

# Force upgrade (use with caution)
helm upgrade redpanda ./helm/redpanda-gke \
  --namespace redpanda \
  --force \
  --values values.yaml
```

### Debugging

```bash
# Get all Helm values
helm get values redpanda -n redpanda --all > current-values.yaml

# Compare with desired values
diff current-values.yaml values-production.yaml

# Check rendered manifests
helm get manifest redpanda -n redpanda | kubectl apply --dry-run=client -f -
```

## Best Practices

### Production Deployments

1. **Always use static IPs** for external LoadBalancers
2. **Enable PodDisruptionBudget** for high availability
3. **Use hard anti-affinity** to spread pods across nodes
4. **Enable monitoring** and configure alerts
5. **Set appropriate resource limits** based on workload
6. **Disable auto-create topics** in production
7. **Use values files** instead of CLI flags for reproducibility
8. **Version control** your values files
9. **Test upgrades** in staging environment first
10. **Have a rollback plan** before upgrades

### Security

1. **Enable network policies** to restrict traffic
2. **Use RBAC** with least privilege
3. **Configure TLS** for external access (not included by default)
4. **Enable SASL authentication** for production
5. **Regularly update** Redpanda version for security patches

### Monitoring

1. **Install Prometheus Operator** for metrics collection
2. **Create Grafana dashboards** for visualization
3. **Set up alerts** for critical metrics
4. **Monitor disk usage** regularly
5. **Track cluster health** metrics

## Next Steps

- Configure TLS/SSL for secure communication
- Set up SASL authentication
- Implement backup strategy
- Configure monitoring and alerting
- Optimize performance based on workload
- Set up multi-region replication (if needed)

## Support

- [Helm Chart README](helm/redpanda-gke/README.md)
- [Redpanda Documentation](https://docs.redpanda.com/)
- [Redpanda Community Slack](https://redpanda.com/slack)
- [GitHub Issues](https://github.com/your-repo/redpanda-gke/issues)
