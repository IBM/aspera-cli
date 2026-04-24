# Aspera CLI on EKS - S3 Synchronization

> [!CAUTION]
> Not tested.

Deploy `ascli` (Aspera CLI) on Amazon EKS for **high-speed S3 bucket synchronization** using Aspera protocol.

## Features

- 🚀 High-speed S3 synchronization with Aspera protocol
- ☸️ Production-ready Kubernetes deployment on EKS
- 🔄 Automated sync with resume capability
- 💾 Persistent sync state tracking (EBS gp3)
- 🔐 Secure credential management

## Prerequisites

1. EKS cluster with `kubectl` access
2. Docker image with Aspera SDK (ECR/Docker Hub)
3. Aspera server credentials
4. AWS credentials for S3 (or IAM role via IRSA)
5. S3 bucket configured

## Quick Start

### 1. Configure Docker Image

Edit `05-deployment-ascli.yaml`:

```yaml
image: your-registry/ascli:version
```

### 2. Configure Credentials

Edit `02-secret-aspera.yaml`:

```yaml
stringData:
  aspera-xfer-password: "your-password"
  aws-access-key-id: "your-key"
  aws-secret-access-key: "your-secret"
```

### 3. Configure S3 Bucket

Edit `03-configmap-ascli.yaml`:

```yaml
data:
  source_pvcl: |
    s3://your-bucket/path
```

### 4. Deploy

```bash
# Automatic
./deploy.sh

# Manual
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-secret-aspera.yaml
kubectl apply -f 03-configmap-ascli.yaml
kubectl apply -f 04-pvc-aspera-data.yaml
kubectl apply -f 05-deployment-ascli.yaml
```

## Configuration

### Environment Variables

- `ASCLI_HOME=/config` - Configuration directory
- `XFER_PASSWORD` - Aspera password (from Secret)
- `AWS_ACCESS_KEY_ID` - AWS key (optional)
- `AWS_SECRET_ACCESS_KEY` - AWS secret (optional)

### Sync Arguments

In `05-deployment-ascli.yaml`:

```yaml
args:
  - "server"
  - "sync"
  - "push"
  - "@preset:data.source_pvcl"  # S3 bucket path using PVCL
  - "@preset:data.conf"         # Additional config
```

## Usage

### Execute Commands

```bash
# Connect to pod
kubectl exec -it -n aspera deployment/aspera-ascli -- /bin/sh

# List files
ascli server browse /path

# Download
ascli server download /remote/file.dat --to-folder=/data/

# Upload
ascli server upload /data/file.dat --to-folder=/remote/
```

### View Logs

```bash
kubectl logs -n aspera deployment/aspera-ascli -f
```

### Monitor

```bash
# Status
kubectl get all -n aspera

# Events
kubectl get events -n aspera --sort-by='.lastTimestamp'
```

## Storage

The PVC stores the **Aspera sync database** which tracks synchronization state and enables resume of interrupted transfers.

- **EBS gp3** (default): Single pod access, 100Gi
- **EFS**: For multi-pod shared access

## Troubleshooting

### Pod Issues

```bash
kubectl describe pod -n aspera -l component=ascli
kubectl logs -n aspera -l component=ascli
```

### Secret Issues

```bash
kubectl get secret aspera-credentials -n aspera -o yaml
```

### Storage Issues

```bash
kubectl describe pvc aspera-data-pvc -n aspera
```

## Security Best Practices

1. Use AWS Secrets Manager or HashiCorp Vault in production
2. Enable RBAC for namespace access control
3. Use IRSA (IAM Roles for Service Accounts) instead of static credentials
4. Scan Docker images for vulnerabilities
5. Implement network policies

## Updates

```bash
# Update image
kubectl set image deployment/aspera-ascli -n aspera \
  ascli=your-registry/ascli:new-version

# Update config
kubectl edit configmap aspera-ascli-config -n aspera
kubectl rollout restart deployment/aspera-ascli -n aspera
```

## Cleanup

```bash
kubectl delete namespace aspera
