# Scénario 2 : Vault Agent - Démonstration de Sécurité

## Objectif
Démontrer comment une application malveillante peut récupérer les secrets d'une autre application dans un environnement Kubernetes + Vault + ArgoCD.

## Scénario d'Attaque
- **Application Légitime** : Une application normale qui stocke ses secrets dans Vault
- **Application Malveillante** : Une application qui exploite les failles de configuration pour voler les secrets de l'autre application

## Architecture de l'Attaque
- **App1 (Légitime)** : Application normale avec ses secrets dans Vault
- **App2 (Malveillante)** : Application qui exploite les failles pour récupérer les secrets d'App1
- **Vecteurs d'Attaque** : 
  - Politiques Vault trop permissives
  - Service accounts avec trop de privilèges
  - Configuration Kubernetes défaillante

## Prérequis
- Cluster Kubernetes avec Vault installé et configuré
- ArgoCD installé (pour le contexte complet)
- Accès à Vault avec le token `dev-token-123`

## Vecteurs d'Attaque Démontrés

### 1. Politiques Vault Trop Permissives
- Configuration de politiques Vault qui permettent l'accès croisé
- Démonstration de l'importance du principe de moindre privilège

### 2. Service Accounts Mal Configurés
- Service accounts avec des permissions excessives
- Exploitation des rôles Kubernetes mal définis

### 3. Configuration ArgoCD Défaillante
- Applications ArgoCD qui peuvent accéder aux secrets d'autres applications
- Manque d'isolation entre les namespaces

## Méthodes de Déploiement

### Option 1 : Déploiement Direct (kubectl)
```sh
./scenarios/02-vault-agent/deploy-scenario2.sh
```

### Option 2 : Déploiement via ArgoCD (Recommandé)
```sh
chmod +x scenarios/02-vault-agent/deploy-argocd.sh
./scenarios/02-vault-agent/deploy-argocd.sh
```


## Étapes de la Démonstration

### 1. Préparer l'Environnement

```sh
kubectl exec -n vault vault-0 -- vault kv put secret/legitimate-app/config \
  username=admin \
  password=super-secret-password \
  apikey=sk-1234567890abcdef \
  databaseurl=postgresql://user:pass@db.internal:5432/prod

kubectl exec -n vault vault-0 -- vault kv put secret/malicious-app/config \
  username=attacker \
  password=attack-pass \
  apikey=sk-attack-key

kubectl exec -n vault vault-0 -- vault kv get secret/legitimate-app/config
kubectl exec -n vault vault-0 -- vault kv get secret/malicious-app/config
```

### 2. Déployer les Applications

#### Via ArgoCD (Recommandé)
```sh
./scenarios/02-vault-agent/deploy-argocd.sh
```

#### Via kubectl direct
```sh
kubectl apply -f scenarios/02-vault-agent/legitimate-app.yaml
kubectl apply -f scenarios/02-vault-agent/malicious-app.yaml

kubectl get pods -n legitimate-app
kubectl get pods -n malicious-app
```

### 3. Démontrer l'Attaque

```sh
# Vérifier que l'app malveillante peut accéder aux secrets de l'app légitime
kubectl logs -n malicious-app deployment/malicious-app -c app

# Tester l'API de l'app malveillante
kubectl port-forward svc/malicious-service -n malicious-app 8082:8080 &
curl http://localhost:8082
```

## Démonstrations de Sécurité

### Démonstration 1 : Vol de Secrets
1. L'application malveillante récupère automatiquement les secrets de l'application légitime
2. Affichage des secrets volés dans les logs et l'API

### Démonstration 2 : Exploitation Continue
1. Modification des secrets de l'app légitime
2. L'app malveillante récupère automatiquement les nouveaux secrets
3. Démontrer la persistance de l'attaque

### Démonstration 3 : Analyse des Vecteurs
1. Vérifier les politiques Vault trop permissives
2. Analyser les permissions des service accounts
3. Identifier les failles de configuration

## Analyse de Sécurité

### Vérifier les Politiques Vault
```sh
kubectl exec -n vault vault-0 -- vault policy read malicious-app-policy
kubectl exec -n vault vault-0 -- vault policy read legitimate-app-policy
```

### Vérifier les Permissions Kubernetes
```sh
kubectl auth can-i get secrets --as=system:serviceaccount:malicious-app:malicious-sa -n legitimate-app
kubectl auth can-i get secrets --as=system:serviceaccount:legitimate-app:legitimate-sa -n malicious-app
```

### Analyser les Rôles Vault
```sh
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/malicious-app-role
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/legitimate-app-role
```

##  Contre-Mesures

### 1. Politiques Vault Strictes
- Limiter l'accès aux secrets uniquement nécessaires
- Utiliser des chemins spécifiques et non génériques

### 2. Service Accounts Isolés
- Un service account par application
- Permissions minimales requises

### 3. Namespaces Isolés
- Séparation stricte des namespaces
- Network policies pour limiter la communication

### 4. Audit et Monitoring
- Logs détaillés des accès Vault
- Alertes sur les accès suspects

##  Nettoyage

### Nettoyage ArgoCD
```sh
kubectl delete -f scenarios/02-vault-agent/argocd-apps.yaml
```

### Nettoyage Direct
```sh
kubectl delete -f scenarios/02-vault-agent/legitimate-app.yaml
kubectl delete -f scenarios/02-vault-agent/malicious-app.yaml

kubectl exec -n vault vault-0 -- vault kv delete secret/legitimate-app/config
kubectl exec -n vault vault-0 -- vault kv delete secret/malicious-app/config

kubectl exec -n vault vault-0 -- vault policy delete malicious-app-policy
kubectl exec -n vault vault-0 -- vault policy delete legitimate-app-policy
```

## Notes de Sécurité

### ATTENTION
Cette démonstration montre des failles de sécurité réelles. Ne pas utiliser en production !

### Vecteurs d'Attaque Réels
- Politiques Vault mal configurées
- Service accounts avec trop de privilèges
- Manque d'isolation entre applications
- Configuration ArgoCD défaillante

### Bonnes Pratiques
- Principe de moindre privilège
- Isolation stricte des applications
- Audit régulier des permissions
- Monitoring des accès aux secrets