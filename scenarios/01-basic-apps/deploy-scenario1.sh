#!/bin/bash

# Scénario 1 : Applications de Base avec ArgoCD
# App1 : Secrets statiques
# App2 : Secrets depuis Vault (sans plugin)

set -e

echo "🚀 Démarrage du Scénario 1 : Applications de Base avec ArgoCD"

# Vérifier qu'ArgoCD est accessible
echo "📋 Vérification d'ArgoCD..."
if ! kubectl get pods -n argocd | grep -q "argocd-repo-server.*Running"; then
    echo "❌ ArgoCD n'est pas en cours d'exécution. Veuillez installer ArgoCD d'abord."
    exit 1
fi

# Vérifier que Vault est accessible (pour App2)
echo "📋 Vérification de Vault..."
if ! kubectl get pods -n vault | grep -q "vault-0.*Running"; then
    echo "❌ Vault n'est pas en cours d'exécution. Veuillez installer Vault d'abord."
    exit 1
fi

echo "✅ ArgoCD et Vault sont accessibles"

# Créer les secrets dans Vault pour App2
echo "🔐 Création des secrets dans Vault pour App2..."
kubectl exec -n vault vault-0 -- vault kv put secret/test2/config \
  username=admin2 \
  password=secret456

echo "✅ Secrets créés dans Vault"

# Vérifier les secrets dans Vault
echo "🔍 Vérification des secrets dans Vault..."
echo "Secret test2/config:"
kubectl exec -n vault vault-0 -- vault kv get secret/test2/config

# Afficher les secrets qui seront utilisés
echo ""
echo "🔐 Secrets qui seront utilisés:"
echo "  App1 (statique): username=admin1, password=secret123"
echo "  App2 (Vault): username=admin2, password=secret456"
echo ""

# Déployer les applications ArgoCD
echo "🚀 Déploiement des applications ArgoCD..."
kubectl apply -f apps.yaml

echo "⏳ Attente du déploiement des applications..."
sleep 20

# Vérifier le statut des applications
echo "📊 Statut des applications ArgoCD:"
kubectl get applications -n argocd

echo ""
echo "📊 Statut des pods:"
kubectl get pods -n static1
kubectl get pods -n static2

echo ""
echo "📊 Statut des services:"
kubectl get svc -n static1
kubectl get svc -n static2

echo ""
echo "🔍 Vérification des secrets déployés:"
echo "Secret App1 (statique):"
kubectl get secret example1 -n static1 -o yaml
echo ""
echo "Secret App2 (créé par initContainer):"
kubectl get secret example2 -n static2 -o yaml

echo ""
echo "✅ Scénario 1 déployé avec succès !"
echo ""
echo "🎯 Pour tester les applications:"
echo "  # Tester App 1 (secrets statiques)"
echo "  kubectl port-forward svc/echo-service -n static1 8080:5678 &"
echo "  curl http://localhost:8080"
echo ""
echo "  # Tester App 2 (secrets depuis Vault)"
echo "  kubectl port-forward svc/echo-service -n static2 8081:5678 &"
echo "  curl http://localhost:8081"
echo ""
echo "🔍 Pour surveiller les logs:"
echo "  kubectl logs -l app=echo-server -n static1 -f"
echo "  kubectl logs -l app=echo-server -n static2 -f"
echo ""
echo "🧹 Pour nettoyer:"
echo "  kubectl delete -f scenarios/01-basic-apps/apps.yaml"
echo "  kubectl exec -n vault vault-0 -- vault kv delete secret/test2/config" 