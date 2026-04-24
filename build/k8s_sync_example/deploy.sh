#!/bin/bash

# Aspera CLI deployment script for EKS
# Usage: ./deploy.sh

set -e

# Extract namespace from YAML file
NAMESPACE=$(sed -n 's/^  name: //p' 01-namespace.yaml)

if [ -z "$NAMESPACE" ]; then
    echo "❌ Could not extract namespace from 01-namespace.yaml"
    exit 1
fi

echo "=========================================="
echo "Aspera CLI Deployment on EKS"
echo "Namespace: $NAMESPACE"
echo "=========================================="

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

# Check cluster connection
echo "📡 Checking EKS cluster connection..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to EKS cluster"
    echo "Check your kubectl and AWS configuration"
    exit 1
fi

echo "✅ Connected to cluster: $(kubectl config current-context)"

# Create namespace
echo ""
echo "📦 Creating namespace $NAMESPACE..."
kubectl apply -f 01-namespace.yaml

# Apply secrets
echo ""
echo "🔐 Applying secrets..."
echo "⚠️  WARNING: Make sure you have configured 02-secret-aspera.yaml with your credentials"
read -p "Have you configured your secrets? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please configure your secrets in 02-secret-aspera.yaml before continuing"
    exit 1
fi
kubectl apply -f 02-secret-aspera.yaml

# Apply configuration
echo ""
echo "⚙️  Applying ascli configuration..."
kubectl apply -f 03-configmap-ascli.yaml

# Create persistent storage
echo ""
echo "💾 Creating persistent storage..."
kubectl apply -f 04-pvc-aspera-data.yaml

# Wait for PVC to be bound
echo "⏳ Waiting for PVC to be ready..."
kubectl wait --for=condition=Bound pvc/aspera-data-pvc -n $NAMESPACE --timeout=120s || {
    echo "⚠️  PVC is not bound yet, but continuing..."
}

# Deploy ascli
echo ""
echo "🚀 Deploying ascli..."
kubectl apply -f 05-deployment-ascli.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
kubectl rollout status deployment/aspera-ascli -n $NAMESPACE --timeout=300s

# Display status
echo ""
echo "=========================================="
echo "✅ Deployment completed successfully!"
echo "=========================================="
echo ""
echo "📊 Resource status:"
kubectl get all -n $NAMESPACE

echo ""
echo "📝 To view logs:"
echo "   kubectl logs -n $NAMESPACE deployment/aspera-ascli -f"
echo ""
echo "🔧 To execute ascli commands:"
echo "   kubectl exec -it -n $NAMESPACE deployment/aspera-ascli -- /bin/sh"
echo ""
echo "📖 See README.md for more information"
