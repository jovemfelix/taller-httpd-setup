#!/bin/bash

# --- Configuration Variables ---
NAMESPACE=cicd-tu-nombre
GITHUB_USER=tu-usuario
GITHUB_TOKEN=tu-token
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

# --- Install Tekton Tasks ---
# oc apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml
# oc apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildah/0.6/buildah.yaml
oc apply -f tasks/buildah.yaml
oc apply -f tasks/git-clone.yaml

# --- Credentials ---
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: github-auth
  annotations:
    tekton.dev/git-0: https://github.com
type: kubernetes.io/basic-auth
stringData:
  username: $GITHUB_USER
  password: $GITHUB_TOKEN
EOF

# --- Permissions ---
oc secrets link pipeline github-auth -n $NAMESPACE
oc adm policy add-scc-to-user privileged -z pipeline -n $NAMESPACE

# --- Storage ---
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pipeline-workspace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# --- Custom Tasks ---

# Task: generate-tag (Combines base tag with commit short-sha)
cat <<'EOF' | oc apply -f -
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: generate-tag
spec:
  params:
    - name: base-tag
      type: string
    - name: commit-sha
      type: string
  results:
    - name: image-tag
      description: Final tag combined with short hash
  steps:
    - name: generate
      image: alpine:latest
      env:
        - name: HOME
          value: /tekton/home
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
      script: |
        #!/bin/sh
        set -e
        SHORT_SHA=$(echo "$(params.commit-sha)" | cut -c1-7)
        FULL_TAG="$(params.base-tag)-${SHORT_SHA}"
        
        printf "%s" "$FULL_TAG" > $(results.image-tag.path)
        echo "Etiqueta generada con éxito: $FULL_TAG"
EOF

# Task: check-image-exists (Validates immutability via Skopeo)
cat <<'EOF' | oc apply -f -
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: check-image-exists
spec:
  params:
    - name: image-url
      type: string
      description: Full URL of the image to check in the registry
  steps:
    - name: check-skopeo
      image: quay.io/skopeo/stable:latest
      env:
        - name: HOME
          value: /tekton/home
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
      script: |
        #!/bin/sh
        echo "Verificando si la imagen ya existe en el registro:"
        echo "URL: $(params.image-url)"
        
        SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
        
        if skopeo inspect --tls-verify=false --creds "serviceaccount:$SA_TOKEN" "docker://$(params.image-url)" > /dev/null 2>&1; then
          echo "❌ ERROR CRÍTICO: ¡La imagen con esta etiqueta ya existe en el registro!"
          echo "Para garantizar la inmutabilidad, la construcción ha sido interrumpida."
          echo "Por favor, incremente la versión (APP_NEW_IMAGE_TAG) o realice un nuevo commit."
          exit 1
        else
          echo "✅ La imagen no existe. Es seguro continuar con la construcción."
          exit 0
        fi
EOF

# Task: update-gitops-repo
cat <<'EOF' | oc apply -f -
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: update-gitops-repo
spec:
  workspaces:
    - name: source
  params:
    - name: gitops-repo-url
      type: string
    - name: image-tag
      type: string
    - name: image-name
      type: string
  steps:
    - name: git-update
      image: alpine/git:v2.36.2      
      workingDir: $(workspaces.source.path)
      env:
        - name: HOME
          value: /tekton/home
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
      script: |
        #!/bin/sh
        set -e
        
        GITOPS_DIR="gitops-repo-$(params.image-name)"
        
        if [ -d "$GITOPS_DIR" ]; then
          echo "Limpiando directorio $GITOPS_DIR anterior..."
          rm -rf "$GITOPS_DIR"
        fi
        
        git clone $(params.gitops-repo-url) "$GITOPS_DIR"
        cd "$GITOPS_DIR"
        
        sed -i "/- image:/ s|image:.*|image: 'image-registry.openshift-image-registry.svc:5000/$(context.taskRun.namespace)/$(params.image-name):$(params.image-tag)'|g" deployment.yaml
        
        git config user.email "pipeline@openshift.com"
        git config user.name "OpenShift Pipeline"
        
        git add deployment.yaml
        
        if git diff --staged --quiet; then
          echo "⚠️  AVISO: No se detectaron cambios en deployment.yaml."
          echo "La etiqueta '$(params.image-tag)' ya está en el repositorio. Ignorando commit y push."
        else
          git commit -m "Update image tag to $(params.image-tag)"
          git push origin main
          echo "✅ ¡Commit y push realizados con éxito!"
        fi
EOF

# --- Pipeline Definition ---
cat <<'EOF' | oc apply -f -
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-and-update-gitops
spec:
  workspaces:
    - name: shared-workspace
  params:
    - name: source-repo-url
      type: string
    - name: gitops-repo-url
      type: string
    - name: image-tag
      type: string
    - name: image-name
      type: string
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
      params:
        - name: url
          value: $(params.source-repo-url)
          
    - name: generate-dynamic-tag
      taskRef:
        name: generate-tag
      runAfter:
        - fetch-source
      params:
        - name: base-tag
          value: $(params.image-tag)
        - name: commit-sha
          value: $(tasks.fetch-source.results.commit)

    - name: check-image
      taskRef:
        name: check-image-exists
      runAfter:
        - generate-dynamic-tag
      params:
        - name: image-url
          value: image-registry.openshift-image-registry.svc:5000/$(context.pipelineRun.namespace)/$(params.image-name):$(tasks.generate-dynamic-tag.results.image-tag)
    
    - name: build-image
      taskRef:
        name: buildah
      runAfter:
        - check-image
      workspaces:
        - name: source
          workspace: shared-workspace
      params:
        - name: IMAGE
          value: image-registry.openshift-image-registry.svc:5000/$(context.pipelineRun.namespace)/$(params.image-name):$(tasks.generate-dynamic-tag.results.image-tag)
          
    - name: update-gitops
      taskRef:
        name: update-gitops-repo
      runAfter:
        - build-image
      retries: 1
      workspaces:
        - name: source
          workspace: shared-workspace
      params:
        - name: gitops-repo-url
          value: $(params.gitops-repo-url)
        - name: image-tag
          value: $(tasks.generate-dynamic-tag.results.image-tag)
        - name: image-name
          value: $(params.image-name)
EOF

# --- Pipeline Execution ---
cat <<EOF | oc create -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: run-workshop-
spec:
  pipelineRef:
    name: build-and-update-gitops
  serviceAccountName: pipeline
  podTemplate:
    securityContext:
      fsGroup: 65532
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: pipeline-workspace
  params:
    - name: source-repo-url
      value: "$GITHUB_SOURCE_REPO"
    - name: gitops-repo-url
      value: "$GITHUB_CONFIG_REPO"
    - name: image-tag
      value: "$APP_NEW_IMAGE_TAG"
    - name: image-name
      value: "$APP_IMAGE_NAME"
EOF