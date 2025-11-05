#!/bin/bash
set -e

# Talos GitOps Setup Script
# This script helps you set up the repository and generate the ArgoCD patch

echo "================================================"
echo "  Talos GitOps Setup Script"
echo "================================================"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed."; exit 1; }
command -v kustomize >/dev/null 2>&1 || { echo "❌ kustomize is required but not installed."; exit 1; }
command -v omnictl >/dev/null 2>&1 || { echo "⚠️  omnictl not found. You'll need it to apply changes."; }
echo "✅ Prerequisites checked"
echo ""

# Get user inputs
read -p "Enter your GitHub username: " GITHUB_USER
read -p "Enter your repository name (default: talos-gitops): " REPO_NAME
REPO_NAME=${REPO_NAME:-talos-gitops}

read -p "Enter your Omni cluster name: " CLUSTER_NAME
read -p "Enter your Talos version (e.g., v1.9.0): " TALOS_VERSION
read -p "Enter your Kubernetes version (e.g., 1.31.0): " K8S_VERSION
read -p "Enter your machine class name (default: default): " MACHINE_CLASS
MACHINE_CLASS=${MACHINE_CLASS:-default}

read -p "Enter number of control plane nodes (default: 1): " CP_COUNT
CP_COUNT=${CP_COUNT:-1}
read -p "Enter number of worker nodes (default: 2): " WORKER_COUNT
WORKER_COUNT=${WORKER_COUNT:-2}

read -p "Enter your MkDocs GitHub repo URL (e.g., https://github.com/user/docs): " DOCS_REPO

echo ""
echo "Configuration:"
echo "  GitHub: https://github.com/$GITHUB_USER/$REPO_NAME"
echo "  Cluster: $CLUSTER_NAME"
echo "  Talos: $TALOS_VERSION"
echo "  Kubernetes: $K8S_VERSION"
echo "  Machine Class: $MACHINE_CLASS"
echo "  Control Planes: $CP_COUNT"
echo "  Workers: $WORKER_COUNT"
echo "  Docs Repo: $DOCS_REPO"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Update cluster-template.yaml
echo "📝 Updating infra/cluster-template.yaml..."
sed -i.bak \
    -e "s|name: talos-cluster|name: $CLUSTER_NAME|" \
    -e "s|version: v1.9.0|version: $TALOS_VERSION|" \
    -e "s|version: 1.31.0|version: $K8S_VERSION|" \
    -e "s|name: default|name: $MACHINE_CLASS|g" \
    -e "s|size: 1|size: $CP_COUNT|" \
    -e "s|size: 2|size: $WORKER_COUNT|" \
    infra/cluster-template.yaml

# Update bootstrap-app-set.yaml
echo "📝 Updating apps/argocd/argocd/bootstrap-app-set.yaml..."
sed -i.bak \
    -e "s|YOUR-USERNAME|$GITHUB_USER|g" \
    -e "s|talos-gitops|$REPO_NAME|g" \
    apps/argocd/argocd/bootstrap-app-set.yaml

# Update mkdocs deployment
echo "📝 Updating apps/default/mkdocs/deployment.yaml..."
sed -i.bak \
    -e "s|YOUR-USERNAME/YOUR-REPO|${DOCS_REPO#https://github.com/}|" \
    apps/default/mkdocs/deployment.yaml

# Clean up backup files
find . -name "*.bak" -delete

# Generate ArgoCD patch
echo "🔨 Generating ArgoCD patch..."

# Ensure patches directory exists
mkdir -p infra/patches

cd apps/argocd/argocd
kustomize build . > /tmp/argocd-full.yaml

echo 'cluster:' > ../../../infra/patches/argocd.yaml
echo '  inlineManifests:' >> ../../../infra/patches/argocd.yaml
echo '    - name: argocd' >> ../../../infra/patches/argocd.yaml
echo '      contents: |' >> ../../../infra/patches/argocd.yaml
sed 's/^/        /' /tmp/argocd-full.yaml >> ../../../infra/patches/argocd.yaml

cd ../../..

echo "✅ ArgoCD patch generated"
echo ""

# Git setup
if [ -d .git ]; then
    echo "📦 Git repository already exists"
else
    echo "📦 Initializing git repository..."
    git init
    git add .
    git commit -m "Initial GitOps setup"
    echo "✅ Git initialized"
    echo ""
    echo "⚠️  Don't forget to:"
    echo "   git remote add origin https://github.com/$GITHUB_USER/$REPO_NAME.git"
    echo "   git push -u origin main"
fi

echo ""
echo "================================================"
echo "  ✅ Setup Complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Remove manual installations (if not done already):"
echo "   kubectl delete namespace argocd"
echo "   kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml"
echo ""
echo "2. Push to GitHub:"
echo "   git push origin main"
echo ""
echo "3. Apply to Omni:"
echo "   cd infra"
echo "   omnictl cluster template sync --file cluster-template.yaml"
echo ""
echo "4. Monitor deployment:"
echo "   kubectl get pods -n argocd"
echo "   kubectl get applications -n argocd"
echo ""
echo "5. Access ArgoCD via Omni Workload Proxy"
echo "   Get admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""
echo "See MIGRATION_GUIDE.md for more details."
echo ""
