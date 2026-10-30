#!/bin/bash
# Construye y sube las 4 imagenes del backend a ECR.
# Ejecutar desde la carpeta Backend (con Docker Desktop abierto):   bash build-push.sh [tag]
set -e
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
TAG="${1:-v1}"

aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR}

for svc in catalog shipments bff notify; do
  echo ""
  echo "=== ${svc} ==="
  docker build -t ${ECR}/rutaexpress-${svc}:${TAG} "ms-rutaexpress-${svc}/ms-rutaexpress-${svc}"
  docker push ${ECR}/rutaexpress-${svc}:${TAG}
done

echo ""
echo "Listo: 4 imagenes subidas con el tag ${TAG}"
