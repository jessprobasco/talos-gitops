# Migrating to GitOps with Omni and ArgoCD

## Overview
This guide will help you migrate from manually installed ArgoCD and MetalLB to a proper GitOps setup using Omni cluster templates. We'll use Omni's Workload Proxy feature instead of MetalLB for simpler networking.

## Prerequisites
- Omni instance with your cluster registered
- `omnictl` CLI installed and configured
- `kubectl` configured for your cluster
- GitHub account (you mentioned having GitHub Pro)
- `kustomize` CLI installed

## Step 1: Clean Up Manual Installations

First, remove the manually installed components:

```bash
# Remove ArgoCD
kubectl delete namespace argocd

# Remove MetalLB
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
kubectl delete -f metallb-config.yaml

# Verify cleanup
kubectl get namespaces | grep -E "argocd|metallb"
```

## Step 2: Create GitHub Repository

1. Create a new repository on GitHub named `talos-gitops` (or your preferred name)
2. Clone it locally:

```bash
git clone https://github.com/YOUR-USERNAME/talos-gitops.git
cd talos-gitops
```

3. Create the directory structure:

```bash
mkdir -p infra/patches
mkdir -p apps/argocd/argocd
mkdir -p apps/default/mkdocs
```

## Step 3: Create Configuration Files

### 3.1 Create `infra/cluster-template.yaml`

```yaml
kind: Cluster
name: talos-cluster  # CHANGE: Match your cluster name in Omni
talos:
  version: v1.9.0  # CHANGE: Match your current Talos version
kubernetes:
  version: 1.31.0  # CHANGE: Match your current Kubernetes version
features:
  enableWorkloadProxy: true  # Enables Omni Workload Proxy
patches:
  - name: argocd
    file: patches/argocd.yaml
---
kind: ControlPlane
machineClass:
  name: default  # CHANGE: Match your machine class in Omni
  size: 1
---
kind: Workers
name: workers
machineClass:
  name: default  # CHANGE: Match your machine class in Omni
  size: 2  # CHANGE: Adjust based on your setup
```

### 3.2 Create `apps/argocd/argocd/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: argocd

resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  - bootstrap-app-set.yaml

patches:
  - target:
      kind: Service
      name: argocd-server
    patch: |-
      - op: add
        path: /metadata/labels/omni.sidero.dev~1workload-proxy
        value: "true"
      - op: add
        path: /metadata/labels/omni.sidero.dev~1workload-proxy-port
        value: "443"
```

### 3.3 Create `apps/argocd/argocd/bootstrap-app-set.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-apps
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: https://github.com/YOUR-USERNAME/talos-gitops.git  # CHANGE THIS
        revision: main
        directories:
          - path: apps/*/*
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/YOUR-USERNAME/talos-gitops.git  # CHANGE THIS
        targetRevision: main
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{index .path.segments 1}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### 3.4 Generate `infra/patches/argocd.yaml`

This is the critical file. Generate it with:

```bash
cd apps/argocd/argocd
kustomize build . > /tmp/argocd-full.yaml

# Create the patch file
cat > ../../infra/patches/argocd.yaml << 'EOF'
cluster:
  inlineManifests:
    - name: argocd
      contents: |
EOF

# Append the manifest with proper indentation
sed 's/^/        /' /tmp/argocd-full.yaml >> ../../infra/patches/argocd.yaml
```

## Step 4: Create MkDocs Application

### 4.1 Create `apps/default/mkdocs/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mkdocs
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mkdocs
  template:
    metadata:
      labels:
        app: mkdocs
    spec:
      containers:
      - name: mkdocs
        image: squidfunk/mkdocs-material:latest
        ports:
        - containerPort: 8000
        command: ["mkdocs"]
        args: ["serve", "--dev-addr=0.0.0.0:8000"]
        volumeMounts:
        - name: docs
          mountPath: /docs
      initContainers:
      - name: git-sync
        image: alpine/git:latest
        command:
        - sh
        - -c
        - |
          git clone https://github.com/YOUR-USERNAME/YOUR-DOCS-REPO.git /docs
        volumeMounts:
        - name: docs
          mountPath: /docs
      volumes:
      - name: docs
        emptyDir: {}
```

### 4.2 Create `apps/default/mkdocs/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mkdocs
  namespace: default
  labels:
    omni.sidero.dev/workload-proxy: "true"
    omni.sidero.dev/workload-proxy-port: "8000"
spec:
  ports:
  - port: 8000
    targetPort: 8000
    name: http
  selector:
    app: mkdocs
  type: ClusterIP
```

### 4.3 Create `apps/default/mkdocs/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

resources:
  - deployment.yaml
  - service.yaml
```

## Step 5: Commit and Push to GitHub

```bash
cd talos-gitops
git add .
git commit -m "Initial GitOps setup with ArgoCD and MkDocs"
git push origin main
```

## Step 6: Apply the Configuration via Omni

```bash
cd infra
omnictl cluster template sync --file cluster-template.yaml
```

This will:
1. Apply the cluster template to Omni
2. Omni will update the cluster configuration
3. ArgoCD will be deployed via the inline manifest
4. ArgoCD will automatically discover and deploy the MkDocs app

## Step 7: Verify Deployment

### Check Omni UI
1. Log into your Omni instance
2. Navigate to your cluster
3. Click on "Workloads" or "Services"
4. You should see ArgoCD and MkDocs listed

### Check via kubectl

```bash
# Check ArgoCD deployment
kubectl get pods -n argocd
kubectl get svc -n argocd

# Check MkDocs deployment
kubectl get pods -n default
kubectl get svc -n default
```

### Access via Omni Workload Proxy

1. In the Omni UI, go to your cluster
2. Click on "Workloads" or the service name
3. You'll see a proxy URL to access your services
4. Click on the ArgoCD link to access the UI
5. Click on the MkDocs link to see your documentation

## Step 8: Get ArgoCD Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

## Troubleshooting

### ArgoCD not deploying
```bash
# Check if the patch was applied
omnictl get cluster talos-cluster -o yaml | grep -A 20 inlineManifests

# Check cluster events
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

### MkDocs not appearing in ArgoCD
```bash
# Check ApplicationSet
kubectl get applicationset -n argocd
kubectl describe applicationset cluster-apps -n argocd

# Check if applications were created
kubectl get applications -n argocd
```

### Workload Proxy not working
- Ensure `features.enableWorkloadProxy: true` is set in cluster template
- Verify service has the correct labels:
  - `omni.sidero.dev/workload-proxy: "true"`
  - `omni.sidero.dev/workload-proxy-port: "PORT"`

## Next Steps

1. **Add Monitoring**: Create `apps/monitoring/prometheus` and `apps/monitoring/grafana`
2. **Migrate to Cilium**: Update cluster template with CNI patch
3. **Add Storage**: Set up Rook/Ceph or OpenEBS for persistent volumes
4. **Add More Apps**: Simply create new directories under `apps/NAMESPACE/APP-NAME`

## Key Benefits of This Approach

- **Declarative**: Everything is in Git
- **Reproducible**: Can recreate cluster from scratch
- **Auditable**: Git history shows all changes
- **Automated**: ArgoCD handles deployments
- **Simple Networking**: Omni Workload Proxy eliminates MetalLB complexity
- **Secure**: Omni handles authentication for workloads

## Reference Documentation

- Sidero Omni Examples: https://github.com/siderolabs/contrib/tree/main/examples/omni
- ArgoCD Documentation: https://argo-cd.readthedocs.io/
- Omni Workload Proxy: https://docs.siderolabs.com/omni/
