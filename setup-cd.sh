#!/bin/bash

# --- Configuration Variables ---
source "$(dirname "$0")/load_env.sh"

# Evalúa la variable. Si falla, el script muere aquí mismo.
: "${NAMESPACE:?Error fatal: NAMESPACE debe estar definida para continuar}"
: "${ARGO_NAMESPACE:?Error fatal: GITHUB_USER debe estar definida para continuar}"
: "${GITHUB_CONFIG_REPO:?Error fatal: GITHUB_CONFIG_REPO debe estar definida para continuar}"
: "${ARGO_APP_NAME:?Error fatal: ARGO_APP_NAME no puede estar vacía}"

# Si el script llega a esta línea, es 100% seguro que ambas variables tienen valor
echo "Todas las credenciales validadas. Ejecutando despliegue..."

# --- Project Configuration ---
oc label namespace $NAMESPACE argocd.argoproj.io/managed-by=argocd-taller --overwrite

# --- ArgoCD Application Definition ---
cat <<EOF | oc apply -f -
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGO_APP_NAME
  namespace: $ARGO_NAMESPACE
  labels:
    env: $ARGO_ENV
    team: $ARGO_TEAM
    author: $ARGO_AUTHOR
spec:
  project: default
  source:
    repoURL: '$GITHUB_CONFIG_REPO'
    targetRevision: HEAD
    path: .
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF