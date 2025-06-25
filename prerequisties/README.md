# KIND

## Install avec Kind

```sh
export KIND_VERSION="v0.20.0"

[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

Need to deactivate default CNI on kind cluster

```yaml
networking:
  disableDefaultCNI: true
```

Testez votre installation :

```sh
kind --version
```

Pour créer un cluster sans CNI :

```sh
kind create cluster --config=cluster-kind-config.yaml
```


## Install avec Minikube

### Prérequis système

```sh
ulimit -n 65536

ulimit -n
```

### Installer Minikube
```
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

Testez votre installation :

```sh
minikube version
```

Pour démarrer un cluster Minikube **sans CNI** :

```sh
minikube start --driver=docker --cni=false --nodes=3 
```

> ⚠️ Sans CNI, il faudra installer manuellement un plugin réseau (ex : Calico, Cilium, etc.)


Pour activer l'ingress :

```sh
minikube addons enable ingress
minikube addons enable csi-hostpath-driver
minikube addons enable default-storageclass
minikube addons enable volumesnapshots
```


## CNI calico


```sh
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
```

```sh
kubectl apply -f calico-operator.yaml
```

## Install Ingress nginx

```sh
kubectl apply -f nginx-ingress.yaml
```
En cas d'erreur 

```sh
kubectl delete job ingress-nginx-admission-create -n ingress-nginx
kubectl delete job ingress-nginx-admission-patch -n ingress-nginx
```
puis réappliquer 

```sh
kubectl apply -f nginx-ingress.yaml
```
## Install prometheus (optional)

```sh
helm upgrade --install -n monitoring --create-namespace prometheus prometheus-community/prometheus
```

## Install Vault 

### Add Helm repository

```sh
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

### Install Vault with Agent Injector

```sh
kubectl create namespace vault

helm install vault hashicorp/vault \
  --namespace vault \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken=dev-token-123 \
  --set injector.enabled=true
```

> ⚠️ **Note importante** : Si seul l'injector se déploie, supprimez l'installation et réinstallez avec la configuration simplifiée ci-dessus. Évitez d'utiliser `server.standalone.enabled=true` en même temps que `server.dev.enabled=true`.

### Vérifier l'installation de Vault

```sh
kubectl get pods -n vault

kubectl get svc -n vault

kubectl port-forward svc/vault -n vault 8200:8200 &
curl http://localhost:8200/v1/sys/health
```

### Vérifier la connectivité Vault

#### Vérifier l'état complet de Vault

```sh
kubectl exec -n vault vault-0 -- vault status

kubectl logs -n vault vault-0 --tail=10

kubectl logs -n vault deployment/vault-agent-injector --tail=10
```

#### Vérifier l'intégration Kubernetes

```sh
kubectl get mutatingwebhookconfigurations | grep vault

kubectl get validatingwebhookconfigurations | grep vault

kubectl describe mutatingwebhookconfigurations vault-agent-injector-cfg
```

#### Tester la connectivité réseau

```sh
kubectl run vault-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -H "X-Vault-Token: dev-token-123" http://vault.vault.svc.cluster.local:8200/v1/sys/health

kubectl exec -n argocd deployment/argocd-repo-server -c repo-server -- \
  curl -H "X-Vault-Token: dev-token-123" http://vault.vault.svc.cluster.local:8200/v1/sys/health
```

#### Vérifier les secrets et l'authentification

```sh
kubectl exec -n vault vault-0 -- vault secrets list

kubectl exec -n vault vault-0 -- vault auth list

kubectl exec -n vault vault-0 -- vault kv put secret/myapp password=test123
kubectl exec -n vault vault-0 -- vault kv get secret/myapp
```

#### Indicateurs de bon fonctionnement

✅ **Pods Vault** : `vault-0` et `vault-agent-injector-*` en état `Running`

✅ **Services** : `vault` et `vault-agent-injector-svc` disponibles

✅ **État Vault** : `Initialized: true`, `Sealed: false`

✅ **Webhooks** : `vault-agent-injector-cfg` présent dans les mutating webhooks

✅ **Connectivité** : Réponse JSON valide de l'API `/v1/sys/health`

✅ **Logs injector** : Messages "Request received: Method=POST URL=/mutate"

### Access Vault UI

```sh
kubectl port-forward svc/vault -n vault 8200:8200
```

- **URL** : http://localhost:8200
- **Token** : `dev-token-123`

### Install Vault CLI (optional)

```sh
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs)"
sudo apt-get update && sudo apt-get install vault

export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN='dev-token-123'

vault status
```
## Install ArgoCD avec Plugin Vault

### Prérequis : Configuration DNS

Avant d'installer ArgoCD, il est important de s'assurer que la résolution DNS fonctionne correctement dans le cluster Minikube pour télécharger le plugin Vault.

#### Vérifier et corriger la configuration CoreDNS

```sh
kubectl get configmap coredns -n kube-system -o yaml

# Corriger la configuration CoreDNS pour forwarder vers les DNS publics
kubectl patch configmap coredns -n kube-system --patch '{
  "data": {
    "Corefile": ".:53 {\n    errors\n    health\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n    }\n    prometheus :9153\n    forward . 8.8.8.8 8.8.4.4\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"
  }
}'

kubectl rollout restart deployment coredns -n kube-system

kubectl get pods -n kube-system -l k8s-app=kube-dns
```

#### Tester la résolution DNS

```sh
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup github.com
```

### Add Helm repository

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### Install ArgoCD

```sh
kubectl create namespace argocd

helm install argocd argo/argo-cd -n argocd
```

### Installer le Plugin Vault

#### Créer le ConfigMap et le patch Deployment

```sh
kubectl apply -f argocd-vault-plugin.yaml
```

Le fichier `argocd-vault-plugin.yaml` contient :
- Un ConfigMap pour déclarer le plugin `argocd-vault-plugin`
- Un patch du Deployment `argocd-repo-server` avec :
  - Un initContainer pour télécharger le binaire du plugin
  - Les variables d'environnement Vault
  - Le montage du binaire dans le container principal

#### Redémarrer le pod repo-server

```sh
kubectl rollout restart deployment argocd-repo-server -n argocd

kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

#### Vérifier l'installation du plugin

```sh
kubectl logs -n argocd deployment/argocd-repo-server -c install-argocd-vault-plugin

kubectl exec -n argocd deployment/argocd-repo-server -c repo-server -- ls -la /usr/local/bin/argocd-vault-plugin

kubectl exec -n argocd deployment/argocd-repo-server -c repo-server -- /usr/local/bin/argocd-vault-plugin --version
```

### Get admin password

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Configure DNS for argocd.local

```sh
echo "127.0.0.1 argocd.local" | sudo tee -a /etc/hosts

cat /etc/hosts | grep argocd
```

### Access ArgoCD UI

- **URL** : https://argocd.local
- **Username** : admin
- **Password** : (use the command above to get it)

### Port forward (alternative access)

```sh
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then access: https://localhost:8080

### Install ArgoCD CLI (optional)

```sh
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

argocd login localhost:8080 --username admin --password <password>
```

### Utilisation du Plugin Vault

#### Exemple de manifest Kubernetes avec Vault

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  annotations:
    avp.kubernetes.io/path: "secret/data/myapp"
stringData:
  password: <vault:secret/data/myapp#password>
  api-key: <vault:secret/data/myapp#api-key>
```

#### Configuration du plugin dans ArgoCD

Le plugin est configuré pour utiliser :
- **VAULT_ADDR** : `http://vault.vault.svc.cluster.local:8200`
- **VAULT_TOKEN** : `dev-token-123`

#### Créer un ApplicationSet avec le plugin

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-set
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - name: myapp
        environment: production
  template:
    metadata:
      name: '{{name}}-{{environment}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-repo/your-app
        targetRevision: HEAD
        path: k8s
        plugin:
          name: argocd-vault-plugin
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{name}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Dépannage

#### Problèmes de téléchargement du plugin

Si le téléchargement du plugin échoue, vérifiez :

```sh
kubectl run network-test --image=curlimages/curl --rm -it --restart=Never -- curl -I https://github.com

kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup github.com
```

#### Problèmes de permissions

```sh
kubectl exec -n argocd deployment/argocd-repo-server -c repo-server -- ls -la /usr/local/bin/argocd-vault-plugin
```

#### Problèmes de configuration Vault

```sh
kubectl exec -n argocd deployment/argocd-repo-server -c repo-server -- curl -H "X-Vault-Token: dev-token-123" http://vault.vault.svc.cluster.local:8200/v1/sys/health
```

---

### Utilisation de Vault dans vos manifests

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
stringData:
  password: <vault:secret/data/myapp#password>
```

---
