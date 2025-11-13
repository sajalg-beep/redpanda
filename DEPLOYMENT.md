# Deployment Guide

This guide provides step-by-step instructions for deploying Redpanda on GKE.

## Pre-Deployment Steps

### 1. Create GKE Cluster

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export CLUSTER_NAME="redpanda-cluster"

# Create GKE cluster
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
  --enable-ip-alias \
  --network="default" \
  --subnetwork="default" \
  --no-enable-basic-auth \
  --no-issue-client-certificate \
  --enable-stackdriver-kubernetes \
  --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver

# Get credentials
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION
```

### 2. Reserve Static IPs (Optional but Recommended)

```bash
# Reserve static IPs for external LoadBalancers
gcloud compute addresses create redpanda-0-ip --region=$REGION
gcloud compute addresses create redpanda-1-ip --region=$REGION
gcloud compute addresses create redpanda-2-ip --region=$REGION

# Get the IP addresses
export IP_0=$(gcloud compute addresses describe redpanda-0-ip --region=$REGION --format="get(address)")
export IP_1=$(gcloud compute addresses describe redpanda-1-ip --region=$REGION --format="get(address)")
export IP_2=$(gcloud compute addresses describe redpanda-2-ip --region=$REGION --format="get(address)")

echo "Broker 0 IP: $IP_0"
echo "Broker 1 IP: $IP_1"
echo "Broker 2 IP: $IP_2"
```

### 3. Update Configuration

Before deploying, update the following files:

#### Update External Domain Names

Edit `k8s/base/04-statefulset.yaml`:

```yaml
# Find this line in the init container (around line 80):
rpk redpanda config set redpanda.advertised_kafka_api[1].address redpanda-${ORDINAL}.example.com

# Replace example.com with your actual domain
rpk redpanda config set redpanda.advertised_kafka_api[1].address redpanda-${ORDINAL}.yourdomain.com
```

#### Configure Static IPs (Optional)

If you reserved static IPs, edit `k8s/base/06-service-external.yaml` and uncomment:

```yaml
annotations:
  networking.gke.io/load-balancer-ip-addresses: "redpanda-0-ip"  # For broker 0
  # networking.gke.io/load-balancer-ip-addresses: "redpanda-1-ip"  # For broker 1
  # networking.gke.io/load-balancer-ip-addresses: "redpanda-2-ip"  # For broker 2
```

## Deployment Steps

### Option 1: Using kubectl

```bash
# Deploy all resources
kubectl apply -f k8s/base/

# Wait for all resources to be created
kubectl wait --for=condition=ready pod -l app=redpanda -n redpanda --timeout=300s
```

### Option 2: Using kustomize

```bash
# Deploy using kustomize
kubectl apply -k k8s/base/

# Wait for all resources to be created
kubectl wait --for=condition=ready pod -l app=redpanda -n redpanda --timeout=300s
```

## Post-Deployment Steps

### 1. Verify Deployment

```bash
# Check namespace
kubectl get namespace redpanda

# Check pods
kubectl get pods -n redpanda -o wide

# Check services
kubectl get svc -n redpanda

# Check PVCs
kubectl get pvc -n redpanda

# Check cluster status
kubectl exec -n redpanda redpanda-0 -- rpk cluster info
```

### 2. Get External IPs

```bash
# Get external LoadBalancer IPs
kubectl get svc -n redpanda -o wide | grep external

# Or get specific IPs
export EXTERNAL_IP_0=$(kubectl get svc redpanda-0-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export EXTERNAL_IP_1=$(kubectl get svc redpanda-1-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export EXTERNAL_IP_2=$(kubectl get svc redpanda-2-external -n redpanda -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Broker 0: $EXTERNAL_IP_0"
echo "Broker 1: $EXTERNAL_IP_1"
echo "Broker 2: $EXTERNAL_IP_2"
```

### 3. Configure DNS

Create DNS A records pointing to the external IPs:

```
redpanda-0.yourdomain.com  →  $EXTERNAL_IP_0
redpanda-1.yourdomain.com  →  $EXTERNAL_IP_1
redpanda-2.yourdomain.com  →  $EXTERNAL_IP_2
```

Using Cloud DNS (example):

```bash
# Create DNS zone (if not exists)
gcloud dns managed-zones create redpanda-zone \
  --dns-name="yourdomain.com." \
  --description="Redpanda DNS zone"

# Add A records
gcloud dns record-sets transaction start --zone=redpanda-zone

gcloud dns record-sets transaction add $EXTERNAL_IP_0 \
  --name=redpanda-0.yourdomain.com. \
  --ttl=300 \
  --type=A \
  --zone=redpanda-zone

gcloud dns record-sets transaction add $EXTERNAL_IP_1 \
  --name=redpanda-1.yourdomain.com. \
  --ttl=300 \
  --type=A \
  --zone=redpanda-zone

gcloud dns record-sets transaction add $EXTERNAL_IP_2 \
  --name=redpanda-2.yourdomain.com. \
  --ttl=300 \
  --type=A \
  --zone=redpanda-zone

gcloud dns record-sets transaction execute --zone=redpanda-zone
```

### 4. Wait for DNS Propagation

```bash
# Test DNS resolution
nslookup redpanda-0.yourdomain.com
nslookup redpanda-1.yourdomain.com
nslookup redpanda-2.yourdomain.com

# Or use dig
dig redpanda-0.yourdomain.com +short
```

## Verification

### Test Internal Connectivity

```bash
# From within the cluster
kubectl run -it --rm debug --image=redpandadata/redpanda:v23.3.5 --restart=Never -- \
  rpk cluster info --brokers redpanda.redpanda.svc.cluster.local:9092
```

### Test External Connectivity

```bash
# From your local machine (after DNS is configured)
rpk cluster info --brokers redpanda-0.yourdomain.com:9094,redpanda-1.yourdomain.com:9094,redpanda-2.yourdomain.com:9094

# Create a topic
rpk topic create test-topic -p 3 -r 3 \
  --brokers redpanda-0.yourdomain.com:9094,redpanda-1.yourdomain.com:9094,redpanda-2.yourdomain.com:9094

# List topics
rpk topic list --brokers redpanda-0.yourdomain.com:9094

# Produce and consume messages
echo "Hello Redpanda" | rpk topic produce test-topic --brokers redpanda-0.yourdomain.com:9094
rpk topic consume test-topic --brokers redpanda-0.yourdomain.com:9094
```

## Monitoring Setup (Optional)

### Install Prometheus Operator

```bash
# Add Prometheus Operator Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus Operator
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Verify ServiceMonitor
kubectl get servicemonitor -n redpanda
```

### Access Grafana

```bash
# Get Grafana password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open http://localhost:3000
# Username: admin
# Password: (from above command)
```

## Troubleshooting

### Check Logs

```bash
# View logs from all brokers
kubectl logs -n redpanda -l app=redpanda --tail=100 -f

# View logs from specific broker
kubectl logs -n redpanda redpanda-0 -f
```

### Check Events

```bash
# View all events in namespace
kubectl get events -n redpanda --sort-by='.lastTimestamp'
```

### Debug Pod Issues

```bash
# Describe pod
kubectl describe pod -n redpanda redpanda-0

# Get pod events
kubectl get events -n redpanda --field-selector involvedObject.name=redpanda-0

# Execute shell in pod
kubectl exec -it -n redpanda redpanda-0 -- /bin/bash
```

### Check Cluster Health

```bash
# Cluster info
kubectl exec -n redpanda redpanda-0 -- rpk cluster info

# Cluster health
kubectl exec -n redpanda redpanda-0 -- rpk cluster health

# Check partition status
kubectl exec -n redpanda redpanda-0 -- rpk topic describe test-topic
```

## Cleanup

### Delete Redpanda Deployment

```bash
# Delete all resources
kubectl delete -f k8s/base/

# Or with kustomize
kubectl delete -k k8s/base/

# Verify deletion
kubectl get all -n redpanda
```

### Delete PVCs (if needed)

```bash
# List PVCs
kubectl get pvc -n redpanda

# Delete PVCs (WARNING: This will delete data)
kubectl delete pvc -n redpanda --all
```

### Release Static IPs

```bash
# Release reserved IPs
gcloud compute addresses delete redpanda-0-ip --region=$REGION
gcloud compute addresses delete redpanda-1-ip --region=$REGION
gcloud compute addresses delete redpanda-2-ip --region=$REGION
```

### Delete GKE Cluster

```bash
# Delete cluster (WARNING: This will delete everything)
gcloud container clusters delete $CLUSTER_NAME --region=$REGION
```

## Next Steps

- Configure TLS/SSL for secure communication
- Set up SASL authentication
- Configure backup and disaster recovery
- Implement monitoring and alerting
- Tune performance based on workload
- Set up multi-region replication (if needed)

## Support

For issues or questions:
- Check the [README.md](README.md) for detailed documentation
- Visit [Redpanda Documentation](https://docs.redpanda.com/)
- Join [Redpanda Community Slack](https://redpanda.com/slack)
