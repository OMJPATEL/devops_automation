#!/usr/bin/env bash
set -euo pipefail

echo "==============================================="
echo " Setting up Minikube Docker environment"
echo "==============================================="

# Use Minikube's Docker daemon
echo "[1] Pointing shell to Minikube Docker..."
eval $(minikube docker-env)

echo "[2] Building images inside Minikube node..."
docker build -t backend:latest ../backend
docker build -t transactions:latest ../transactions
docker build -t studentportfolio:latest ../studentportfolio

echo "[3] Showing images inside Minikube:"
docker images | grep -E "backend|transactions|studentportfolio|mongo|nginx"

echo "==============================================="
echo " Applying Kubernetes manifests"
echo "==============================================="

kubectl apply -f mongo-service.yaml
kubectl apply -f mongo-statefulset.yaml

kubectl apply -f backend-secret.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml

kubectl apply -f transactions-deployment.yaml
kubectl apply -f transactions-service.yaml

kubectl apply -f studentportfolio-deployment.yaml
kubectl apply -f studentportfolio-service.yaml

kubectl apply -f nginx-configmap.yaml
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml

kubectl apply -f backend-hpa.yaml
kubectl apply -f transactions-hpa.yaml

echo "==============================================="
echo " Restarting deployments to use fresh images"
echo "==============================================="

kubectl rollout restart deployment backend
kubectl rollout restart deployment transactions
kubectl rollout restart deployment studentportfolio
kubectl rollout restart deployment nginx

echo "==============================================="
echo " Waiting for Pods to become Ready"
echo "==============================================="

kubectl wait --for=condition=ready pod -l app=mongo --timeout=120s
kubectl wait --for=condition=ready pod -l app=backend --timeout=120s
kubectl wait --for=condition=ready pod -l app=transactions --timeout=120s
kubectl wait --for=condition=ready pod -l app=studentportfolio --timeout=120s
kubectl wait --for=condition=ready pod -l app=nginx --timeout=120s

echo "==============================================="
echo " All pods should now be ready"
echo "==============================================="

kubectl get pods -o wide

echo "==============================================="
echo " To open the application, run:"
echo "   minikube service nginx"
echo "==============================================="
