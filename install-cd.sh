#!/bin/bash

# --- Configuration Variables ---
source "$(dirname "$0")/load_env.sh"

# Evalúa la variable. Si falla, el script muere aquí mismo.
: "${ARGO_NAMESPACE:?Error fatal: GITHUB_USER debe estar definida para continuar}"

# Si el script llega a esta línea, es 100% seguro que ambas variables tienen valor
echo "Todas las credenciales validadas. Ejecutando despliegue..."

# --- Project Setup ---
if ! oc get project "$ARGO_NAMESPACE" &> /dev/null; then
    oc new-project "$ARGO_NAMESPACE" > /dev/null
else
    oc project "$ARGO_NAMESPACE" > /dev/null
fi

# --- ArgoCD Instance Installation ---
cat <<EOF | oc apply -f -
---
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: argocd-taller
  namespace: $ARGO_NAMESPACE
spec:
  controller:
    resources:
      limits:
        cpu: "2"
        memory: 2Gi
      requests:
        cpu: 250m
        memory: 1Gi
  grafana:
    enabled: false
    ingress:
      enabled: false
    route:
      enabled: false
  ha:
    enabled: false
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  monitoring:
    enabled: false
  notifications:
    enabled: false
  prometheus:
    enabled: false
    ingress:
      enabled: false
    route:
      enabled: false
  rbac:
    defaultPolicy: ""
    policy: |
      g, system:authenticated, role:admin
  redis:
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  repo:
    resources:
      limits:
        cpu: "1"
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 256Mi
  resourceExclusions: "- apiGroups:\n  - tekton.dev\n  clusters:\n  - '*'\n  kinds:\n    - TaskRun\n  - PipelineRun\n"
  server:
    autoscale:
      enabled: false
    grpc:
      ingress:
        enabled: false
    ingress:
      enabled: false
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 125m
        memory: 128Mi
    route:
      enabled: true
    service:
      type: ""
  sso:
    dex:
      openShiftOAuth: true
      resources:
        limits:
          cpu: 500m
          memory: 256Mi
        requests:
          cpu: 250m
          memory: 128Mi
    provider: dex
EOF