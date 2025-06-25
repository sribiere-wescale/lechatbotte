#!/bin/bash

# Scénario 2 : Vault Agent - Démonstration de Sécurité
# Démontrer comment une application malveillante peut voler les secrets d'une autre application

set -e

echo "🚨 Démarrage du Scénario 2 : Démonstration de Sécurité - Vol de Secrets"

# Vérifier que Vault est accessible
echo "📋 Vérification de Vault..."
if ! kubectl get pods -n vault | grep -q "vault-0.*Running"; then
    echo "❌ Vault n'est pas en cours d'exécution. Veuillez installer Vault d'abord."
    exit 1
fi

echo "✅ Vault est accessible"

# Créer les secrets dans Vault
echo "🔐 Création des secrets dans Vault..."
kubectl exec -n vault vault-0 -- vault kv put secret/legitimate-app/config \
  username=admin \
  password=super-secret-password \
  api-key=sk-1234567890abcdef \
  database-url=postgresql://user:pass@db.internal:5432/prod

kubectl exec -n vault vault-0 -- vault kv put secret/malicious-app/config \
  username=attacker \
  password=attack-pass \
  api-key=sk-attack-key

echo "✅ Secrets créés dans Vault"

# Vérifier les secrets dans Vault
echo "🔍 Vérification des secrets dans Vault..."
echo "Secret legitimate-app/config:"
kubectl exec -n vault vault-0 -- vault kv get secret/legitimate-app/config
echo ""
echo "Secret malicious-app/config:"
kubectl exec -n vault vault-0 -- vault kv get secret/malicious-app/config

# Configurer l'authentification Kubernetes dans Vault (si pas déjà fait)
echo "🔧 Configuration de l'authentification Kubernetes dans Vault..."
kubectl exec -n vault vault-0 -- vault auth enable kubernetes 2>/dev/null || echo "Authentification Kubernetes déjà activée"

# Créer les politiques Vault MALVEILLANTES (qui permettent l'attaque)
echo "🚨 Création des politiques Vault MALVEILLANTES..."

# Créer un fichier temporaire pour la politique légitime
cat > /tmp/legitimate-app-policy.hcl <<EOF
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
}
EOF

# Créer un fichier temporaire pour la politique malveillante
cat > /tmp/malicious-app-policy.hcl <<EOF
# Accès à ses propres secrets
path "secret/data/malicious-app/*" {
  capabilities = ["read"]
}
# 🚨 ACCÈS MALVEILLANT aux secrets de l'app légitime
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
}
EOF

# Copier les fichiers dans le pod Vault et appliquer les politiques
kubectl cp /tmp/legitimate-app-policy.hcl vault/vault-0:/tmp/legitimate-app-policy.hcl
kubectl cp /tmp/malicious-app-policy.hcl vault/vault-0:/tmp/malicious-app-policy.hcl

kubectl exec -n vault vault-0 -- vault policy write legitimate-app-policy /tmp/legitimate-app-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write malicious-app-policy /tmp/malicious-app-policy.hcl

# Nettoyer les fichiers temporaires
rm -f /tmp/legitimate-app-policy.hcl /tmp/malicious-app-policy.hcl

echo "⚠️  POLITIQUES MALVEILLANTES CRÉÉES - L'attaque est possible !"

# Créer les rôles Kubernetes pour Vault Agent
echo "🔑 Création des rôles Kubernetes pour Vault Agent..."

# Rôle pour l'app légitime
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/legitimate-app-role \
  bound_service_account_names=legitimate-sa \
  bound_service_account_namespaces=legitimate-app \
  policies=legitimate-app-policy \
  ttl=1h

# Rôle MALVEILLANT pour l'app malveillante
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/malicious-app-role \
  bound_service_account_names=malicious-sa \
  bound_service_account_namespaces=malicious-app \
  policies=malicious-app-policy \
  ttl=1h

echo "✅ Configuration Vault terminée (avec failles de sécurité)"

# Déployer les applications
echo "🚀 Déploiement des applications..."
echo "📦 Déploiement de l'application légitime..."
kubectl apply -f scenarios/02-vault-agent/legitimate-app.yaml

echo "🤖 Déploiement de l'application malveillante..."
kubectl apply -f scenarios/02-vault-agent/malicious-app.yaml

echo "⏳ Attente du déploiement..."
sleep 30

# Vérifier le statut des déploiements
echo "📊 Statut des déploiements:"
echo "Application Légitime:"
kubectl get pods -n legitimate-app
echo ""
echo "Application Malveillante:"
kubectl get pods -n malicious-app

echo ""
echo "📊 Statut des services:"
echo "Application Légitime:"
kubectl get svc -n legitimate-app
echo ""
echo "Application Malveillante:"
kubectl get svc -n malicious-app

echo ""
echo "🚨 DÉMONSTRATION DE SÉCURITÉ PRÊTE !"
echo ""
echo "🎯 Pour démontrer l'attaque:"
echo "  # Vérifier que l'app malveillante a volé les secrets"
echo "  kubectl logs -n malicious-app deployment/malicious-app -c app"
echo ""
echo "  # Tester l'API de l'app malveillante (expose les secrets volés)"
echo "  kubectl port-forward svc/malicious-service -n malicious-app 8082:8080 &"
echo "  curl http://localhost:8082"
echo ""
echo "  # Tester l'API de l'app légitime (fonctionne normalement)"
echo "  kubectl port-forward svc/legitimate-service -n legitimate-app 8083:8080 &"
echo "  curl http://localhost:8083"
echo ""
echo "🔍 Pour analyser les failles de sécurité:"
echo "  # Voir les politiques malveillantes"
echo "  kubectl exec -n vault vault-0 -- vault policy read malicious-app-policy"
echo ""
echo "  # Vérifier les permissions des service accounts"
echo "  kubectl auth can-i get secrets --as=system:serviceaccount:malicious-app:malicious-sa -n legitimate-app"
echo ""
echo "  # Surveiller les logs d'attaque"
echo "  kubectl logs -n malicious-app deployment/malicious-app -c app -f"
echo ""
echo "🧹 Pour nettoyer:"
echo "  kubectl delete -f scenarios/02-vault-agent/legitimate-app.yaml"
echo "  kubectl delete -f scenarios/02-vault-agent/malicious-app.yaml"
echo "  kubectl exec -n vault vault-0 -- vault kv delete secret/legitimate-app/config"
echo "  kubectl exec -n vault vault-0 -- vault kv delete secret/malicious-app/config"
echo "  kubectl exec -n vault vault-0 -- vault policy delete malicious-app-policy"
echo "  kubectl exec -n vault vault-0 -- vault policy delete legitimate-app-policy" 