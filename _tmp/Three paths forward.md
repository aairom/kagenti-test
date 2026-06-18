### Three paths forward

**Option A — Fastest (resize minikube, reuse existing work):**

```bash
minikube stop --profile minikube-1
minikube delete --profile minikube-1
minikube start --profile minikube-1 --driver=podman \
  --container-runtime=cri-o --memory=8192 --cpus=4
# Then re-run the Kagenti installer with --skip-cluster
cd kagenti && scripts/kind/setup-kagenti.sh --skip-cluster --with-ui --with-backend
```



**Option B — Cleanest (dedicated Kind cluster, fully supported path):**

```bash
brew install kind
cd kagenti
scripts/kind/setup-kagenti.sh --with-ui --with-spire --with-backend
open http://kagenti-ui.localtest.me:8080
```



**Option C — Minimal auth only (install Keycloak on current cluster):** Unblocks the Operator's auth wiring without the UI:

```bash
helm install keycloak bitnami/keycloak --namespace keycloak --create-namespace \
  --set auth.adminUser=admin --set auth.adminPassword=admin \
  --kube-context minikube-1
```