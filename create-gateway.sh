#!/bin/bash
# Crea el API Gateway completo en un solo paso:
#   - rutas /api/... protegidas con JWT (Azure) hacia el BFF
#   - rutas publicas hacia el frontend (para servirlo por HTTPS)
# Uso:  bash create-gateway.sh <host-ELB-del-BFF> <host-ELB-del-frontend>
set -e
export MSYS_NO_PATHCONV=1   # evita que Git Bash modifique las rutas que empiezan con /

BFF_HOST="$1"
FRONT_HOST="$2"
if [ -z "$BFF_HOST" ] || [ -z "$FRONT_HOST" ]; then
  echo "Uso: bash create-gateway.sh <host-ELB-del-BFF> <host-ELB-del-frontend>"
  exit 1
fi

REGION="us-east-1"
TENANT_ID="fdb3d6ab-c533-4a33-ab84-23ae397254fc"
AUDIENCE="eb713dd4-c607-4248-8b4d-671864ed5c89"
ISSUER="https://login.microsoftonline.com/${TENANT_ID}/v2.0"
BFF="http://${BFF_HOST}"
FRONT="http://${FRONT_HOST}"

echo "Creando API..."
API_ID=$(aws apigatewayv2 create-api --region $REGION --name rutaexpress-gateway --protocol-type HTTP \
  --cors-configuration AllowOrigins=http://localhost:5173,AllowHeaders=authorization,content-type,AllowMethods=GET,POST,PUT,DELETE,OPTIONS \
  --query ApiId --output text)
echo "  ApiId: ${API_ID}"

echo "Creando authorizer JWT..."
AUTH_ID=$(aws apigatewayv2 create-authorizer --region $REGION --api-id $API_ID --name rutaexpress-jwt-auth \
  --authorizer-type JWT --identity-source '$request.header.Authorization' \
  --jwt-configuration Audience=${AUDIENCE},Issuer=${ISSUER} \
  --query AuthorizerId --output text)
echo "  AuthorizerId: ${AUTH_ID}"

crear_integracion() {
  aws apigatewayv2 create-integration --region $REGION --api-id $API_ID \
    --integration-type HTTP_PROXY --integration-method ANY --payload-format-version 1.0 \
    --integration-uri "$1" --query IntegrationId --output text
}

crear_ruta() {   # $1 = route key, $2 = integration id, $3 = JWT | NONE
  if [ "$3" = "JWT" ]; then
    aws apigatewayv2 create-route --region $REGION --api-id $API_ID --route-key "$1" \
      --target "integrations/$2" --authorization-type JWT --authorizer-id $AUTH_ID > /dev/null
  else
    aws apigatewayv2 create-route --region $REGION --api-id $API_ID --route-key "$1" \
      --target "integrations/$2" --authorization-type NONE > /dev/null
  fi
  echo "  ruta: $1  [$3]"
}

echo "Creando integraciones (una por ruta, con su path completo)..."
I_SERV=$(crear_integracion "${BFF}/api/catalog/services")
I_SERV_ID=$(crear_integracion "${BFF}/api/catalog/services/{id}")
I_FLOTA=$(crear_integracion "${BFF}/api/catalog/fleet-capacity")
I_ENV=$(crear_integracion "${BFF}/api/shipments")
I_ENV_ID=$(crear_integracion "${BFF}/api/shipments/{id}")
I_ENV_ST=$(crear_integracion "${BFF}/api/shipments/{id}/status")
I_FRONT_PROXY=$(crear_integracion "${FRONT}/{proxy}")
I_FRONT_ROOT=$(crear_integracion "${FRONT}/")

echo "Creando rutas..."
crear_ruta "GET /api/catalog/services"          $I_SERV    JWT
crear_ruta "POST /api/catalog/services"         $I_SERV    JWT
crear_ruta "GET /api/catalog/services/{id}"     $I_SERV_ID JWT
crear_ruta "GET /api/catalog/fleet-capacity"    $I_FLOTA   JWT
crear_ruta "GET /api/shipments"                 $I_ENV     JWT
crear_ruta "POST /api/shipments"                $I_ENV     JWT
crear_ruta "GET /api/shipments/{id}"            $I_ENV_ID  JWT
crear_ruta "PUT /api/shipments/{id}/status"     $I_ENV_ST  JWT
crear_ruta 'ANY /{proxy+}'                      $I_FRONT_PROXY NONE
crear_ruta "GET /"                              $I_FRONT_ROOT  NONE

echo "Publicando..."
DEPLOY_ID=$(aws apigatewayv2 create-deployment --region $REGION --api-id $API_ID --query DeploymentId --output text)
aws apigatewayv2 create-stage --region $REGION --api-id $API_ID --stage-name '$default' --deployment-id $DEPLOY_ID > /dev/null

URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com"
echo ""
echo "===================================================="
echo "  API GATEWAY LISTO:  ${URL}"
echo "===================================================="
echo "Pendiente:"
echo "  1. Anto: agregar ${URL}/dashboard como Redirect URI (SPA) en el App Registration del frontend."
echo "  2. Reconstruir el frontend con VITE_API_BASE_URL=${URL} y VITE_AZURE_REDIRECT_URI=${URL}/dashboard"
echo "  3. kubectl set env deployment/rutaexpress-notify TRACKING_BASE_URL=${URL}/shipments/ -n rutaexpress"
echo "Si cambias rutas despues, publica con:"
echo "  aws apigatewayv2 create-deployment --api-id ${API_ID} --stage-name '\$default'"
