#!/bin/bash

# --- Configuration Variables ---
NAMESPACE=pac-renato
GITHUB_TOKEN=tu-token
GITHUB_SECRET=abc123
GITHUB_SOURCE_REPO=https://github.com/jovemfelix/taller-httpd-application-engineering.git
GITHUB_CONFIG_REPO=https://github.com/jovemfelix/taller-httpd-release-engineering.git
APP_NEW_IMAGE_TAG='1.0.1'
APP_IMAGE_NAME='httpd-demo' 

# --- Project Setup ---
if ! oc get project "$NAMESPACE" &> /dev/null; then
    oc new-project "$NAMESPACE" > /dev/null
else
    oc project "$NAMESPACE" > /dev/null
fi

# --- Secret ---
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: webhook-secret
  namespace: $NAMESPACE
type: Opaque
stringData:
  # 1. El token para autenticar en la API de GitHub (Para Status/PRs)
  github.token: "$GITHUB_TOKEN"
  # 2. El secret para validar que el Webhook realmente viene de GitHub
  webhook.secret: "$GITHUB_SECRET"
EOF

# --- Repository ---
cat <<EOF | oc apply -f -
apiVersion: pipelinesascode.tekton.dev/v1alpha1
kind: Repository
metadata:
  name: mi-repo-pac
  namespace: $NAMESPACE
spec:
  url: "$GITHUB_CONFIG_REPO" # Reemplaza con tu URL exacta
  git_provider:
    # Vinculamos el token de la API de GitHub
    secret:
      name: "webhook-secret"
      key: "github.token"
    # Vinculamos el secret de validación del Webhook
    webhook_secret:
      name: "webhook-secret"
      key: "webhook.secret"
EOF

WEBHOOK_URL=$(oc get route pipelines-as-code-controller -n openshift-pipelines -o jsonpath='{.spec.host}')
echo "======================================================="
echo "🔗 URL DEL WEBHOOK (Cópiala en GitHub):"
echo "http://$WEBHOOK_URL"
echo "======================================================="