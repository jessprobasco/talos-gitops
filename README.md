# Talos GitOps Template

This repository contains a GitOps setup for Talos Linux clusters managed by Omni, with ArgoCD for application deployment.

## Quick Start

1. Fork/clone this repository
2. Update the following files with your information:
   - `infra/cluster-template.yaml`: Update cluster name, versions, and machine classes
   - `apps/argocd/argocd/bootstrap-app-set.yaml`: Update GitHub repository URLs (2 places)
   - `apps/default/mkdocs/deployment.yaml`: Update your docs repository URL

3. Generate the ArgoCD patch:
   ```bash
   cd apps/argocd/argocd
   kustomize build . > /tmp/argocd-full.yaml
   
   # Create the patch file with proper structure
   echo 'cluster:' > ../../infra/patches/argocd.yaml
   echo '  inlineManifests:' >> ../../infra/patches/argocd.yaml
   echo '    - name: argocd' >> ../../infra/patches/argocd.yaml
   echo '      contents: |' >> ../../infra/patches/argocd.yaml
   sed 's/^/        /' /tmp/argocd-full.yaml >> ../../infra/patches/argocd.yaml
   ```

4. Commit and push to your GitHub repository

5. Apply to Omni:
   ```bash
   cd infra
   omnictl cluster template sync --file cluster-template.yaml
   ```

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for detailed instructions.

## Repository Structure

```
.
├── README.md
├── MIGRATION_GUIDE.md
├── infra/
│   ├── cluster-template.yaml
│   └── patches/
│       └── argocd.yaml (to be generated)
└── apps/
    ├── argocd/
    │   └── argocd/
    │       ├── kustomization.yaml
    │       └── bootstrap-app-set.yaml
    └── default/
        └── mkdocs/
            ├── deployment.yaml
            ├── service.yaml
            └── kustomization.yaml
```

## Adding New Applications

To add a new application, simply create a new directory structure:

```bash
mkdir -p apps/NAMESPACE/APP-NAME
cd apps/NAMESPACE/APP-NAME
# Create your Kubernetes manifests or kustomization.yaml
```

ArgoCD will automatically discover and deploy the application thanks to the ApplicationSet.

## Features

- ✅ Declarative cluster management via Omni
- ✅ GitOps with ArgoCD
- ✅ Omni Workload Proxy (no MetalLB needed)
- ✅ Automatic application discovery
- ✅ Self-healing deployments

## Documentation

- [Migration Guide](MIGRATION_GUIDE.md) - Complete step-by-step migration instructions
- [Sidero Omni Docs](https://docs.siderolabs.com/omni/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
