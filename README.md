# LeChatBotte - Démonstration de Sécurité avec Vault et ArgoCD

## 🎯 Objectif

Ce projet démontre comment une application malveillante peut voler les secrets d'une application légitime en utilisant différentes approches de gestion des secrets avec HashiCorp Vault et ArgoCD.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│  Application    │    │  Application    │
│   Légitime      │    │  Malveillante   │
│                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Secrets     │ │    │ │ Secrets     │ │
│ │ Management  │ │    │ │ Management  │ │
│ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┼───► ArgoCD
                                 │
                                 └───► Vault Server
```

## 📋 Prérequis

### 1. Infrastructure de Base
```bash
# Installer les prérequis de base
cd prerequisties/
./install-prerequisites.sh
```

### 2. Vault Server
```bash
# Installer et configurer Vault
cd prerequisties/
./install-vault.sh
```

### 3. ArgoCD
```bash
# Installer ArgoCD
cd prerequisties/
./install-argocd.sh
```

### 4. Vault Secrets Operator (VSO)
```bash
# Ajouter le repository Helm HashiCorp
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Installer Vault Secrets Operator
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault \
  --create-namespace

# Vérifier l'installation
kubectl get pods -n vault | grep vault-secrets-operator
kubectl get crd | grep vault
```

## 🚀 Scénarios de Démonstration

### Scénario 1 : Secrets Statiques avec Vault
**Objectif** : Démontrer le vol de secrets avec des secrets statiques et Vault sans plugin ArgoCD.

**Fichiers** : `scenarios/01-basic-apps/`

**Déploiement** :
```bash
cd scenarios/01-basic-apps/
kubectl apply -f argocd-apps.yaml
```

**Test** :
```bash
kubectl port-forward svc/static1-service -n static1 8081:8080 &
kubectl port-forward svc/static2-service -n static2 8082:8080 &
```

### Scénario 2 : Vault Agent avec Templates
**Objectif** : Démontrer le vol de secrets via Vault Agent avec des templates dynamiques.

**Fichiers** : `scenarios/02-vault-agent/`

**Déploiement** :
```bash
cd scenarios/02-vault-agent/
kubectl apply -f argocd-apps.yaml
```

**Test** :
```bash
kubectl port-forward svc/legitimate-service -n legitimate-app 8081:8080 &
kubectl port-forward svc/malicious-service -n malicious-app 8082:8080 &
```

### Scénario 3 : Vault Secrets Operator (VSO)
**Objectif** : Démontrer le vol de secrets via Vault Secrets Operator avec VaultDynamicSecrets.

**Fichiers** : `scenarios/03-vault-secrets-operator/`

**Déploiement** :
```bash
cd scenarios/03-vault-secrets-operator/
kubectl apply -f argocd-apps.yaml
```

**Test** :
```bash
kubectl port-forward svc/legitimate-service -n legitimate-app 8081:8080 &
kubectl port-forward svc/malicious-service -n malicious-app 8082:8080 &
```

## 🔍 Points de Sécurité Démonstrés

### 1. Isolation des Secrets
- Chaque méthode a ses propres mécanismes de contrôle d'accès
- Rôles Vault pour limiter l'accès aux secrets
- Namespaces Kubernetes pour l'isolation

### 2. Vulnérabilités
- **Scénario 1** : Accès direct aux secrets via ServiceAccount
- **Scénario 2** : Templates Vault Agent pointant vers d'autres secrets
- **Scénario 3** : VaultDynamicSecrets créés pour voler des secrets

### 3. Détection
- Logs Vault montrent les tentatives d'accès aux secrets
- Logs des applications révèlent les secrets volés
- Interface ArgoCD pour visualiser les déploiements

## 🌐 Accès aux Interfaces

### ArgoCD
```bash
# Récupérer le mot de passe admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**URL** : https://localhost:8080
**Utilisateur** : admin
**Mot de passe** : (récupéré ci-dessus)

### Applications de Démonstration
- **Application Légitime** : http://localhost:8081
- **Application Malveillante** : http://localhost:8082

## 📊 Monitoring et Debugging

### Vérifier les Pods
```bash
# Scénario 1
kubectl get pods -n static1
kubectl get pods -n static2

# Scénario 2
kubectl get pods -n legitimate-app
kubectl get pods -n malicious-app

# Scénario 3
kubectl get pods -n legitimate-app
kubectl get pods -n malicious-app
```

### Vérifier les Secrets Vault
```bash
# Lister les secrets
kubectl exec -n vault vault-0 -- vault kv list secret/

# Voir un secret spécifique
kubectl exec -n vault vault-0 -- vault kv get secret/legitimate-app/config
```

### Vérifier les VaultDynamicSecrets (Scénario 3)
```bash
kubectl get vaultdynamicsecrets -n legitimate-app
kubectl get vaultdynamicsecrets -n malicious-app
```

## 🧹 Nettoyage

### Supprimer les Applications ArgoCD
```bash
# Scénario 1
kubectl delete application static1-app -n argocd
kubectl delete application static2-app -n argocd

# Scénario 2
kubectl delete application legitimate-app -n argocd
kubectl delete application malicious-app -n argocd

# Scénario 3
kubectl delete application legitimate-app-vso -n argocd
kubectl delete application malicious-app-vso -n argocd
```

### Supprimer Vault Secrets Operator
```bash
helm uninstall vault-secrets-operator -n vault
```

## 🔧 Configuration Avancée

### Rôles Vault pour l'Authentification Kubernetes
```bash
# Créer un rôle pour l'app légitime
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/legitimate-app-role \
  bound_service_account_names=legitimate-sa \
  bound_service_account_namespaces=legitimate-app \
  policies=legitimate-app-policy \
  ttl=1h

# Créer un rôle pour l'app malveillante
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/malicious-app-role \
  bound_service_account_names=malicious-sa \
  bound_service_account_namespaces=malicious-app \
  policies=malicious-app-policy \
  ttl=1h
```

### Politiques Vault
```bash
# Politique pour l'app légitime
kubectl exec -n vault vault-0 -- vault policy write legitimate-app-policy - <<EOF
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
}
EOF

# Politique pour l'app malveillante
kubectl exec -n vault vault-0 -- vault policy write malicious-app-policy - <<EOF
path "secret/data/malicious-app/*" {
  capabilities = ["read"]
}
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
}
EOF
```

## 📝 Notes Importantes

1. **Sécurité** : Ce projet est conçu pour la démonstration et l'éducation. Ne pas utiliser en production.
2. **Réseau** : Assurez-vous que les images Docker peuvent être téléchargées.
3. **Ressources** : Les démonstrations nécessitent suffisamment de ressources CPU/mémoire.
4. **Ports** : Les ports 8080, 8081, 8082 sont utilisés pour les démonstrations.

## 🤝 Contribution

Ce projet est destiné à l'éducation et à la sensibilisation aux bonnes pratiques de sécurité dans la gestion des secrets avec Kubernetes et Vault. 