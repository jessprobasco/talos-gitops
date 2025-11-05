# Quick Reference Summary

## What We're Changing

### Before (Manual Installation)
- ArgoCD manually installed via kubectl apply
- MetalLB manually installed via kubectl apply
- LoadBalancer IPs: 192.168.7.51-100
- No GitOps workflow

### After (Declarative GitOps)
- ArgoCD deployed via Omni cluster templates (inline manifests)
- No MetalLB (using Omni Workload Proxy instead)
- Everything managed via Git
- Automatic application discovery and deployment

## Key Files Explained

### `infra/cluster-template.yaml`
- Main Omni cluster configuration
- Defines Talos/K8s versions
- References patches to apply
- Specifies machine classes and counts

### `infra/patches/argocd.yaml`
- Contains the full ArgoCD installation manifest
- Generated from kustomize build
- Applied as inline manifest during cluster sync
- Includes Omni Workload Proxy labels

### `apps/argocd/argocd/bootstrap-app-set.yaml`
- ArgoCD ApplicationSet for automatic discovery
- Watches the Git repository
- Creates Applications for each directory in `apps/*/*`
- Enables self-healing and auto-sync

### `apps/argocd/argocd/kustomization.yaml`
- Combines standard ArgoCD installation
- Adds the bootstrap ApplicationSet
- Patches argocd-server service for Omni Workload Proxy

### `apps/default/mkdocs/*`
- Example application deployment
- Shows proper structure for apps
- Uses Omni Workload Proxy for access

## Critical Configuration Points

### 1. GitHub Repository URLs
Update in `apps/argocd/argocd/bootstrap-app-set.yaml`:
```yaml
repoURL: https://github.com/YOUR-USERNAME/talos-gitops.git
```
This appears **twice** in the file.

### 2. Cluster Details
Update in `infra/cluster-template.yaml`:
- Cluster name
- Talos version
- Kubernetes version
- Machine class names
- Node counts

### 3. MkDocs Repository
Update in `apps/default/mkdocs/deployment.yaml`:
```yaml
git clone https://github.com/YOUR-USERNAME/YOUR-DOCS-REPO.git /docs
```

### 4. Omni Workload Proxy Labels
Required on services you want to access:
```yaml
metadata:
  labels:
    omni.sidero.dev/workload-proxy: "true"
    omni.sidero.dev/workload-proxy-port: "8000"
```

## Migration Checklist

- [ ] Clean up manual installations
  - [ ] Delete argocd namespace
  - [ ] Delete metallb resources
- [ ] Create GitHub repository
- [ ] Update configuration files
  - [ ] infra/cluster-template.yaml
  - [ ] apps/argocd/argocd/bootstrap-app-set.yaml (2 places)
  - [ ] apps/default/mkdocs/deployment.yaml
- [ ] Generate ArgoCD patch
  - [ ] Run kustomize build
  - [ ] Create infra/patches/argocd.yaml
- [ ] Commit and push to GitHub
- [ ] Apply via omnictl
  - [ ] cd infra
  - [ ] omnictl cluster template sync --file cluster-template.yaml
- [ ] Verify deployment
  - [ ] Check ArgoCD pods
  - [ ] Check Applications
  - [ ] Access via Workload Proxy
- [ ] Get ArgoCD admin password
- [ ] Deploy test application (MkDocs)

## Commands Quick Reference

### Cleanup Manual Installation
```bash
kubectl delete namespace argocd
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
kubectl delete -f metallb-config.yaml  # if you have this file
```

### Generate ArgoCD Patch
```bash
cd apps/argocd/argocd
kustomize build . > /tmp/argocd-full.yaml
echo 'cluster:' > ../../infra/patches/argocd.yaml
echo '  inlineManifests:' >> ../../infra/patches/argocd.yaml
echo '    - name: argocd' >> ../../infra/patches/argocd.yaml
echo '      contents: |' >> ../../infra/patches/argocd.yaml
sed 's/^/        /' /tmp/argocd-full.yaml >> ../../infra/patches/argocd.yaml
cd ../../..
```

### Git Operations
```bash
git init
git add .
git commit -m "Initial GitOps setup"
git remote add origin https://github.com/YOUR-USERNAME/talos-gitops.git
git push -u origin main
```

### Apply to Omni
```bash
cd infra
omnictl cluster template sync --file cluster-template.yaml
```

### Verification
```bash
# Check ArgoCD
kubectl get pods -n argocd
kubectl get svc -n argocd
kubectl get applications -n argocd
kubectl get applicationset -n argocd

# Check MkDocs
kubectl get pods -n default
kubectl get svc -n default

# Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

## Omni Workload Proxy Benefits

1. **No LoadBalancer needed**: No MetalLB, no external IPs to manage
2. **Built-in authentication**: Omni handles SSO/authentication
3. **Easy access**: Click links in Omni UI to access services
4. **Secure by default**: Traffic goes through Omni's secure proxy
5. **Works everywhere**: No network configuration needed

## How ApplicationSet Auto-Discovery Works

The bootstrap ApplicationSet watches your Git repository and:

1. Scans for directories matching `apps/*/*` pattern
2. For each directory found (e.g., `apps/default/mkdocs`):
   - Creates an Application named after the directory basename (`mkdocs`)
   - Deploys to the namespace from the path (`default`)
   - Applies manifests from that directory
3. Automatically syncs changes from Git
4. Self-heals if someone manually modifies resources

This means you can add new applications by simply:
```bash
mkdir -p apps/NAMESPACE/APP-NAME
# Add your manifests
git add . && git commit -m "Add new app" && git push
```

## Troubleshooting Tips

### ArgoCD not deploying
```bash
# Check the patch was applied
omnictl get cluster YOUR-CLUSTER -o yaml | grep -A 20 inlineManifests

# Check for errors in cluster events
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

### Applications not appearing
```bash
# Check ApplicationSet
kubectl get applicationset -n argocd
kubectl describe applicationset cluster-apps -n argocd

# Check generated Applications
kubectl get applications -n argocd
```

### Workload Proxy not working
- Verify `enableWorkloadProxy: true` in cluster template
- Check service has correct labels
- Look for service in Omni UI under Workloads

### Git repository not accessible
- Ensure repository is public (or add credentials if private)
- Verify URLs in bootstrap-app-set.yaml match your repo
- Check ArgoCD can reach GitHub (network/firewall)

## Next Steps After Setup

1. **Add Monitoring**
   ```bash
   mkdir -p apps/monitoring/{prometheus,grafana}
   # Add Helm charts or manifests
   ```

2. **Migrate to Cilium**
   - Add CNI patch to cluster template
   - Update cluster via omnictl

3. **Add Persistent Storage**
   - For single node: OpenEBS + local-path
   - For HA: Rook/Ceph (needs 3+ nodes with block devices)

4. **Add More Applications**
   - Just create directories under `apps/NAMESPACE/APP-NAME`
   - Git push and ArgoCD deploys automatically

## Important Notes

- **Flannel → Cilium**: You're currently on Flannel. Migrate later when ready.
- **Storage**: You don't have persistent storage configured yet. Add when needed.
- **Monitoring**: Not included in initial setup. Add as separate applications.
- **Public Repo**: Bootstrap assumes public GitHub repo. For private repos, add credentials.

## Support Resources

- Migration Guide: See `MIGRATION_GUIDE.md`
- Sidero Slack: https://slack.dev.talos-systems.io/
- ArgoCD Docs: https://argo-cd.readthedocs.io/
- Omni Docs: https://docs.siderolabs.com/omni/
