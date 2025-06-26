# Scénario 3 : Vol de Secrets via Vault Secrets Operator (VSO)

## 🎯 Objectif

Démontrer comment une application malveillante peut voler les secrets d'une application légitime en utilisant Vault Secrets Operator (VSO) et ArgoCD.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│  Application    │    │  Application    │
│   Légitime      │    │  Malveillante   │
│                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ VSO Client  │ │    │ │ VSO Client  │ │
│ │ (légitime)  │ │    │ │ (malveill.) │ │
│ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┼───► Vault Secrets Operator
                                 │
                                 └───► Vault Server
```

## 🔧 Composants

### Applications
- **Application Légitime** : Utilise VSO pour récupérer ses propres secrets
- **Application Malveillante** : Utilise VSO pour récupérer ses secrets ET voler ceux de l'app légitime

### Vault Secrets Operator
- Gère les `VaultAuth` et `VaultDynamicSecret` CRDs
- Authentification Kubernetes
- Récupération automatique des secrets depuis Vault

##  Déploiement

### 1. Prérequis
- Vault Server opérationnel
- Vault Secrets Operator installé
- ArgoCD configuré

### 2. Création des secrets dans Vault
```bash
# Secrets pour l'app légitime
kubectl exec -n vault vault-0 -- vault kv put secret/legitimate-app/config \
  username="legitimate_user" \
  password="legitimate_pass123" \
  apikey="legitimate_api_key_456" \
  databaseurl="postgresql://legitimate-db:5432/legitimate_db"

# Secrets pour l'app malveillante
kubectl exec -n vault vault-0 -- vault kv put secret/malicious-app/config \
  username="malicious_user" \
  password="malicious_pass789" \
  apikey="malicious_api_key_123"
```

### 3. Déploiement via ArgoCD
```bash
kubectl apply -f argocd-apps.yaml
```

### 4. Vérification
```bash
# Vérifier les pods
kubectl get pods -n legitimate-app
kubectl get pods -n malicious-app

# Vérifier les VaultDynamicSecrets
kubectl get vaultdynamicsecrets -n legitimate-app
kubectl get vaultdynamicsecrets -n malicious-app

# Tester les services
kubectl port-forward svc/legitimate-service -n legitimate-app 8081:8080 &
kubectl port-forward svc/malicious-service -n malicious-app 8082:8080 &
```

## Démonstration de l'Attaque

### Application Légitime
- Récupère ses propres secrets via VSO
- Affiche ses secrets dans les logs et via HTTP

### Application Malveillante
- Récupère ses propres secrets via VSO
- **VOLE les secrets de l'app légitime** en créant un VaultDynamicSecret pointant vers les secrets légitimes
- Affiche les secrets volés dans les logs et via HTTP

## Points Clés de Sécurité

1. **Isolation des secrets** : VSO permet de contrôler l'accès aux secrets via les rôles Vault
2. **Vulnérabilité** : Si une application a accès aux secrets d'une autre, elle peut les voler
3. **Détection** : Les logs Vault montrent les tentatives d'accès aux secrets

## Monitoring

- Logs des applications pour voir les secrets récupérés
- Logs Vault pour voir les accès aux secrets
- Interface ArgoCD pour visualiser les déploiements 