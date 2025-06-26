#!/bin/bash

echo "🚀 Déploiement du Scénario 3 : Vol de Secrets via VSO"
echo "=================================================="

# Vérifier que Vault est accessible
echo "📋 Vérification de Vault..."
kubectl exec -n vault vault-0 -- vault status > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Vault n'est pas accessible"
    exit 1
fi
echo "✅ Vault est accessible"

# Vérifier que VSO est installé
echo "📋 Vérification de Vault Secrets Operator..."
kubectl get crd vaultauths.secrets.hashicorp.com > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Vault Secrets Operator n'est pas installé"
    echo "Installez-le avec: helm install vault-secrets-operator hashicorp/vault-secrets-operator"
    exit 1
fi
echo "✅ Vault Secrets Operator est installé"

# Créer les secrets dans Vault
echo "🔐 Création des secrets dans Vault..."
kubectl exec -n vault vault-0 -- vault kv put secret/legitimate-app/config \
  username="legitimate_user" \
  password="legitimate_pass123" \
  apikey="legitimate_api_key_456" \
  databaseurl="postgresql://legitimate-db:5432/legitimate_db"

kubectl exec -n vault vault-0 -- vault kv put secret/malicious-app/config \
  username="malicious_user" \
  password="malicious_pass789" \
  apikey="malicious_api_key_123"

echo "✅ Secrets créés dans Vault"

# Déployer via ArgoCD
echo "🚀 Déploiement via ArgoCD..."
kubectl apply -f argocd-apps.yaml

echo "⏳ Attente de la synchronisation ArgoCD..."
sleep 30

# Vérifier le statut
echo "📊 Statut des applications ArgoCD:"
kubectl get applications -n argocd | grep -E "(legitimate-app-vso|malicious-app-vso)"

echo "📊 Statut des pods:"
kubectl get pods -n legitimate-app 2>/dev/null || echo "Namespace legitimate-app pas encore créé"
kubectl get pods -n malicious-app 2>/dev/null || echo "Namespace malicious-app pas encore créé"

echo ""
echo "🎯 Pour tester les applications:"
echo "kubectl port-forward svc/legitimate-service -n legitimate-app 8081:8080 &"
echo "kubectl port-forward svc/malicious-service -n malicious-app 8082:8080 &"
echo ""
echo "🌐 Interface ArgoCD: http://localhost:8080"
echo "📱 Application Légitime: http://localhost:8081"
echo "🚨 Application Malveillante: http://localhost:8082" 