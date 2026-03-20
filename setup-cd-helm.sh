#!/bin/bash

# --- Configuration Variables ---
source "$(dirname "$0")/load_env.sh"

# Evalúa la variable. Si falla, el script muere aquí mismo.
: "${ARGO_APP_NAME:?Error fatal: ARGO_APP_NAME no puede estar vacía}"
: "${ARGO_ENV:?Error fatal: ARGO_ENV debe estar definida para continuar}"
: "${ARGO_NAMESPACE:?Error fatal: GITHUB_USER debe estar definida para continuar}"
: "${ARGO_TEAM:?Error fatal: ARGO_TEAM debe estar definida para continuar}"
: "${ARGO_TEAM:?Error fatal: ARGO_TEAM debe estar definida para continuar}"
: "${GITHUB_CONFIG_REPO:?Error fatal: GITHUB_CONFIG_REPO debe estar definida para continuar}"
: "${GITHUB_HELM_REPO:?Error fatal: GITHUB_HELM_REPO debe estar definida para continuar}"
: "${NAMESPACE:?Error fatal: NAMESPACE debe estar definida para continuar}"

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
    author: $ARGO_TEAM
spec:
  project: default
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true

  # Usamos únicamente 'sources' (plural)
  sources:
    # 1. El Repositorio del Helm Chart (Repo A)
    - repoURL: '$GITHUB_HELM_REPO'
      targetRevision: HEAD
      path: . # La carpeta donde está el Chart.yaml
      helm:
        valueFiles:
          # ¡AQUÍ ESTÁ LA MAGIA! Escapamos la variable con \$
          - \$values/values-dev.yaml 

    # 2. El Repositorio de Release Engineering (Repo B)
    - repoURL: '$GITHUB_CONFIG_REPO'
      targetRevision: $GITHUB_CONFIG_BRANCH
      ref: values 
EOF