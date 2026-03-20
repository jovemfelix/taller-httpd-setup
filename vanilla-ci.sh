#!/bin/bash

# --- Configuration Variables ---
source "$(dirname "$0")/load_env.sh"

# Evalúa la variable. Si falla, el script muere aquí mismo.
: "${NAMESPACE:?Error fatal: NAMESPACE debe estar definida para continuar}"
: "${GITHUB_CONFIG_REPO:?Error fatal: GITHUB_CONFIG_REPO debe estar definida para continuar}"
: "${APP_NEW_IMAGE_TAG:?Error fatal: APP_NEW_IMAGE_TAG no puede estar vacía}"
: "${APP_IMAGE_NAME:?Error fatal: APP_IMAGE_NAME no puede estar vacía}"

# Si el script llega a esta línea, es 100% seguro que ambas variables tienen valor
echo "Todas las credenciales validadas. Ejecutando despliegue..."

# --- Project Setup ---
if ! oc get project "$NAMESPACE" &> /dev/null; then
    oc new-project "$NAMESPACE" > /dev/null
else
    oc project "$NAMESPACE" > /dev/null
fi

# --- TriggerBinding ---
cat <<'EOF' | oc apply -f -
apiVersion: triggers.tekton.dev/v1alpha1
kind: TriggerBinding
metadata:
  name: github-push-binding
spec:
  params:
    - name: git-repo-url
      value: $(body.repository.clone_url)
    - name: git-revision
      value: $(body.head_commit.id) # Usaremos el Commit SHA como Image Tag
    - name: repo-name
      value: $(body.repository.name)
EOF

# --- TriggerTemplate ---
cat <<EOF | oc apply -f -
apiVersion: triggers.tekton.dev/v1alpha1
kind: TriggerTemplate
metadata:
  name: pipeline-template
spec:
  params:
    - name: git-repo-url
      description: URL del repositorio fuente
    - name: git-revision
      description: El SHA del commit
    - name: repo-owner
      description: Dueño del repositorio
    - name: repo-name
      description: Nombre del repositorio
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: run-workshop-webhook-
      spec:
        pipelineRef:
          name: build-and-update-gitops
        serviceAccountName: pipeline
        workspaces:
          - name: shared-workspace
            persistentVolumeClaim:
              claimName: pipeline-workspace
        params:
          # Escapamos el $ de Tekton para que Bash lo ignore
          - name: source-repo-url
            value: \$(tt.params.git-repo-url)
            
          # Dejamos este $ normal para que Bash inyecte la variable de entorno
          - name: gitops-repo-url
            value: "$GITHUB_CONFIG_REPO"
            
          - name: image-tag
            value: "$APP_NEW_IMAGE_TAG"
          - name: image-name
            value: \$(tt.params.repo-name)
EOF

# --- EventListener ---
cat <<'EOF' | oc apply -f -
apiVersion: triggers.tekton.dev/v1alpha1
kind: EventListener
metadata:
  name: github-listener
spec:
  serviceAccountName: pipeline
  triggers:
    - name: github-push-trigger
      bindings:
        - ref: github-push-binding
      template:
        ref: pipeline-template
EOF

echo "Verificando la ruta del Webhook..."

if ! oc get route el-github-listener -n "$NAMESPACE" &> /dev/null; then
    echo "Exponiendo el servicio el-github-listener..."
    oc expose svc el-github-listener -n "$NAMESPACE"
    echo "✅ Ruta creada con éxito."
else
    echo "✅ La ruta el-github-listener ya existe. Omitiendo creación."
fi

WEBHOOK_URL=$(oc get route el-github-listener -n "$NAMESPACE" -o jsonpath='{.spec.host}')
echo "======================================================="
echo "🔗 URL DEL WEBHOOK (Cópiala en GitHub):"
echo "http://$WEBHOOK_URL"
echo "======================================================="