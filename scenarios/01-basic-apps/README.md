# Scénario 1 : Applications de Base avec ArgoCD (Approche Hybride)

## Objectif
Déployer 2 applications simples via ArgoCD avec des approches différentes pour les secrets :
- **App1 (static1)** : Secrets statiques encodés en base64
- **App2 (static2)** : Secrets récupérés depuis Vault via l'API (sans plugin ArgoCD)

## Prérequis
- Cluster Kubernetes avec ArgoCD installé et configuré
- Vault installé et configuré (pour App2)
- Accès au cluster Kubernetes

## Architecture

### App1 (static1)
- ✅ Secrets statiques dans le fichier YAML
- ✅ Pas de dépendance à Vault
- ✅ Déploiement simple et rapide

### App2 (static2)
- ✅ Secrets stockés dans Vault
- ✅ Récupération via initContainer utilisant l'API Vault
- ✅ Pas d'utilisation du plugin ArgoCD Vault
- ✅ Démonstration d'intégration directe avec Vault

## Étapes du scénario

### 1. Déployer les applications via ArgoCD

```sh
# Exécuter le script de déploiement
./scenarios/01-basic-apps/deploy-scenario1.sh

# Ou déployer manuellement
kubectl apply -f scenarios/01-basic-apps/apps.yaml
```

### 2. Vérifier les déploiements

```sh
# Vérifier les applications ArgoCD
kubectl get applications -n argocd

# Vérifier les pods
kubectl get pods -n static1
kubectl get pods -n static2

# Vérifier les services
kubectl get svc -n static1
kubectl get svc -n static2

# Vérifier les secrets
kubectl get secret example1 -n static1 -o yaml
kubectl get secret example2 -n static2 -o yaml
```

### 3. Tester les applications

```sh
# Tester App 1 (secrets statiques)
kubectl port-forward svc/echo-service -n static1 8080:5678 &
curl http://localhost:8080

# Tester App 2 (secrets depuis Vault)
kubectl port-forward svc/echo-service -n static2 8081:5678 &
curl http://localhost:8081
```

## 🎮 Défis à relever

### Défi 1 : Modification des secrets App1 (statique)
1. Modifier le secret `example1` dans le namespace `static1`
2. Vérifier que l'application se met à jour automatiquement

```sh
# Modifier le secret
kubectl patch secret example1 -n static1 --type='json' -p='[{"op": "replace", "path": "/data/username", "value": "bmV3YWRtaW4="}]'

# Vérifier la mise à jour
kubectl logs -l app=echo-server -n static1 --tail=10
```

### Défi 2 : Modification des secrets App2 (Vault)
1. Modifier le secret `test2/config` dans Vault
2. Redémarrer le pod pour récupérer les nouveaux secrets

```sh
# Modifier le secret dans Vault
kubectl exec -n vault vault-0 -- vault kv put secret/test2/config \
  username=newadmin2 \
  password=newsecret456

# Redémarrer le pod pour récupérer les nouveaux secrets
kubectl rollout restart deployment echo-deployment -n static2

# Vérifier la mise à jour
kubectl logs -l app=echo-server -n static2 --tail=10
```

### Défi 3 : Analyse de sécurité
1. Comparer les deux approches de gestion des secrets
2. Identifier les avantages et inconvénients de chaque méthode
3. Analyser les risques de sécurité

```sh
# Vérifier les permissions sur les secrets
kubectl auth can-i get secrets -n static1
kubectl auth can-i get secrets -n static2

# Lister les secrets
kubectl get secrets -n static1
kubectl get secrets -n static2

# Vérifier l'accès à Vault depuis le cluster
kubectl run vault-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -H "X-Vault-Token: dev-token-123" http://vault.vault.svc.cluster.local:8200/v1/sys/health
```

## 🧹 Nettoyage

```sh
# Supprimer les applications ArgoCD
kubectl delete -f scenarios/01-basic-apps/apps.yaml

# Supprimer les secrets de Vault (optionnel)
kubectl exec -n vault vault-0 -- vault kv delete secret/test2/config
```

## 📝 Notes importantes

### App1 (static1)
- Les secrets sont stockés directement dans Kubernetes
- Les secrets sont visibles dans l'historique Git (attention à la sécurité)
- Déploiement simple et rapide
- Pas de dépendance externe

### App2 (static2)
- Les secrets sont stockés dans Vault
- Récupération via initContainer utilisant l'API Vault
- Les secrets ne sont pas visibles dans Git
- Nécessite un redémarrage pour récupérer les nouveaux secrets
- Dépendance à Vault

## 🔐 Secrets utilisés

### App1 (statique)
- username=admin1, password=secret123
- Encodés en base64 : YWRtaW4x, c2VjcmV0MTIz

### App2 (Vault)
- username=admin2, password=secret456
- Stockés dans Vault : `secret/data/test2/config`

## 🔍 Debugging

### Vérifier les logs de l'initContainer
```sh
kubectl logs -n static2 deployment/echo-deployment -c vault-init
```

### Tester l'API Vault directement
```sh
kubectl run vault-api-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -H "X-Vault-Token: dev-token-123" \
  http://vault.vault.svc.cluster.local:8200/v1/secret/data/test2/config
``` 