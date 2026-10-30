#!/bin/bash
# Deploy inicial a EKS. Ejecutar desde la carpeta Backend:   bash deploy.sh [--con-frontend]
set -e

echo "===================================================="
echo "  RutaExpress - Deploy inicial a EKS"
echo "===================================================="

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo ""
echo "Cuenta AWS: ${ACCOUNT_ID}"
echo "ECR URL:    ${ECR_URL}"

echo ""
echo "Revisando que no queden valores pendientes en los manifests..."
if grep -n -E 'RABBITMQ_ADDRESSES: "a"|IP_PRIVADA_EC2|\{\{RDS_|REEMPLAZAR' ./k8s/secrets.yaml; then
  echo ""
  echo "ERROR: k8s/secrets.yaml tiene valores sin completar (endpoints de RDS o IP de RabbitMQ)."
  echo "Sacalos de las Outputs del stack de CloudFormation y vuelve a correr este script."
  exit 1
fi

echo ""
echo "Actualizando kubeconfig..."
aws eks update-kubeconfig --region ${REGION} --name rutaexpress

echo ""
echo "Actualizando la URL de ECR en los manifests (sirve para cualquier cuenta anterior)..."
find ./k8s -type f -name "*.yaml" \
  -exec sed -i -E "s#[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com#${ECR_URL}#g; s#\{\{ECR_URL\}\}#${ECR_URL}#g" {} \;

echo ""
echo "Creando namespace y secrets..."
kubectl apply -f ./k8s/namespace.yaml
kubectl apply -f ./k8s/secrets.yaml

echo ""
echo "Desplegando microservicios..."
kubectl apply -f ./k8s/catalog-deployment.yaml
kubectl apply -f ./k8s/shipments-deployment.yaml
kubectl apply -f ./k8s/bff-deployment.yaml
kubectl apply -f ./k8s/notify-deployment.yaml

if [ "$1" = "--con-frontend" ]; then
  echo ""
  echo "Desplegando frontend (el Service crea el Load Balancer aunque la imagen aun no exista)..."
  kubectl apply -f ./k8s/frontend-deployment.yaml
fi

echo ""
echo "Esperando que los pods queden Ready..."
kubectl rollout status deployment/rutaexpress-catalog -n rutaexpress --timeout=300s
kubectl rollout status deployment/rutaexpress-shipments -n rutaexpress --timeout=300s
kubectl rollout status deployment/rutaexpress-bff -n rutaexpress --timeout=300s
kubectl rollout status deployment/rutaexpress-notify -n rutaexpress --timeout=300s

####################################################
# LOAD BALANCERS
####################################################

esperar_lb() {
  local svc="$1"
  for i in $(seq 1 40); do
    local host
    host=$(kubectl get svc "$svc" -n rutaexpress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$host" ]; then
      echo "$host"
      return 0
    fi
    sleep 15
  done
  return 1
}

echo ""
echo "Esperando el Load Balancer del BFF..."
BFF_HOSTNAME=$(esperar_lb rutaexpress-bff) || BFF_HOSTNAME=""
echo "===================================================="
echo "  BFF:      ${BFF_HOSTNAME:-pendiente}"

if [ "$1" = "--con-frontend" ]; then
  FRONT_HOSTNAME=$(esperar_lb rutaexpress-frontend) || FRONT_HOSTNAME=""
  echo "  FRONTEND: ${FRONT_HOSTNAME:-pendiente}"
fi
echo "===================================================="
echo ""
echo "Siguiente paso: bash create-gateway.sh <host-del-BFF> <host-del-frontend>"
