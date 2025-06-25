# Scénario 1 : Applications de Base avec ArgoCD

## Objectif
Déployer 2 applications simples via ArgoCD avec des secrets stockés dans Vault.
Voir si le chat botté peut voler les secrets

## Prérequis
- Cluster Kubernetes avec Vault installé et configuré
- ArgoCD installé 
- Accès à Vault avec le token `dev-token-123`

## Étapes du scénario

### 1. Préparer les secrets dans Vault

```sh
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN='dev-token-123'

# Créer les secrets pour les 2 applications
kubectl exec -n vault vault-0 -- vault kv put secret/test1/config \
  username=admin1 \
  password=secret123

kubectl exec -n vault vault-0 -- vault kv put secret/test2/config \
  username=admin2 \
  password=secret456

# Vérifier les secrets
kubectl exec -n vault vault-0 -- vault kv get secret/test1/config
kubectl exec -n vault vault-0 -- vault kv get secret/test2/config
```

### 2. Déployer les applications via ArgoCD

```sh
# Créer les applications ArgoCD
kubectl apply -f scenarios/01-basic-apps/apps.yaml

# Vérifier les applications
kubectl get applications -n argocd
```

### 3. Vérifier les déploiements

```sh
# Vérifier les pods
kubectl get pods -n static1
kubectl get pods -n static2

# Vérifier les services
kubectl get svc -n static1
kubectl get svc -n static2
```

### 4. Tester les applications

```sh
# Tester App 1
kubectl port-forward svc/echo-service -n static1 8080:5678 &
curl http://localhost:8080

# Tester App 2
kubectl port-forward svc/echo-service -n static2 8081:5678 &
curl http://localhost:8081
```

## 🎮 Défis à relever

### Défi 1 : Modification des secrets
1. Modifier le secret `test1/config` dans Vault
2. Vérifier que l'application se met à jour automatiquement

```sh
# Modifier le secret
kubectl exec -n vault vault-0 -- vault kv put secret/test1/config \
  username=newadmin1 \
  password=newsecret123

# Vérifier la mise à jour
kubectl logs -l app=echo-server -n static1 --tail=10
```

## 🧹 Nettoyage

```sh
# Supprimer les applications ArgoCD
kubectl delete -f scenarios/01-basic-apps/apps.yaml

# Supprimer les secrets de Vault (optionnel)
kubectl exec -n vault vault-0 -- vault kv delete secret/test1/config
kubectl exec -n vault vault-0 -- vault kv delete secret/test2/config
```

## 📝 Notes importantes

- Les applications utilisent l'ArgoCD Vault Plugin pour récupérer les secrets
- Les secrets sont stockés dans Vault et récupérés dynamiquement
- Les applications affichent les secrets dans leur réponse HTTP 