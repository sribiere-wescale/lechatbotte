#!/bin/bash

# Scénario 2 : Déploiement via ArgoCD - Démonstration de Sécurité
# Déployer les applications légitime et malveillante via ArgoCD pour une interface graphique

set -e

echo "🚀 Démarrage du déploiement ArgoCD pour le Scénario 2 : Démonstration de Sécurité"

# Vérifier qu'ArgoCD est accessible
echo "📋 Vérification d'ArgoCD..."
if ! kubectl get pods -n argocd | grep -q "argocd-server.*Running"; then
    echo "❌ ArgoCD n'est pas en cours d'exécution. Veuillez installer ArgoCD d'abord."
    exit 1
fi

echo "✅ ArgoCD est accessible"

# Vérifier que Vault est accessible
echo "📋 Vérification de Vault..."
if ! kubectl get pods -n vault | grep -q "vault-0.*Running"; then
    echo "❌ Vault n'est pas en cours d'exécution. Veuillez installer Vault d'abord."
    exit 1
fi

echo "✅ Vault est accessible"

# Créer les secrets dans Vault (si pas déjà fait)
echo "🔐 Vérification des secrets dans Vault..."
if ! kubectl exec -n vault vault-0 -- vault kv get secret/legitimate-app/config >/dev/null 2>&1; then
    echo "📝 Création des secrets pour l'application légitime..."
    kubectl exec -n vault vault-0 -- vault kv put secret/legitimate-app/config \
      username=admin \
      password=super-secret-password \
      apikey=sk-1234567890abcdef \
      databaseurl=postgresql://user:pass@db.internal:5432/prod
fi

if ! kubectl exec -n vault vault-0 -- vault kv get secret/malicious-app/config >/dev/null 2>&1; then
    echo "📝 Création des secrets pour l'application malveillante..."
    kubectl exec -n vault vault-0 -- vault kv put secret/malicious-app/config \
      username=attacker \
      password=attack-pass \
      apikey=sk-attack-key
fi

echo "✅ Secrets Vault vérifiés"

# Configurer les politiques Vault (si pas déjà fait)
echo "🔧 Configuration des politiques Vault..."
if ! kubectl exec -n vault vault-0 -- vault policy read legitimate-app-policy >/dev/null 2>&1; then
    echo "📝 Création de la politique pour l'app légitime..."
    
    # Créer un fichier temporaire pour la politique légitime
    cat > /tmp/legitimate-app-policy.hcl <<EOF
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
}
EOF
    
    kubectl cp /tmp/legitimate-app-policy.hcl vault/vault-0:/tmp/legitimate-app-policy.hcl
    kubectl exec -n vault vault-0 -- vault policy write legitimate-app-policy /tmp/legitimate-app-policy.hcl
    rm -f /tmp/legitimate-app-policy.hcl
fi

if ! kubectl exec -n vault vault-0 -- vault policy read malicious-app-policy >/dev/null 2>&1; then
    echo "📝 Création de la politique MALVEILLANTE pour l'app malveillante..."
    
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
    
    kubectl cp /tmp/malicious-app-policy.hcl vault/vault-0:/tmp/malicious-app-policy.hcl
    kubectl exec -n vault vault-0 -- vault policy write malicious-app-policy /tmp/malicious-app-policy.hcl
    rm -f /tmp/malicious-app-policy.hcl
fi

echo "✅ Politiques Vault configurées"

# Configurer les rôles Kubernetes (si pas déjà fait)
echo "🔑 Configuration des rôles Kubernetes..."
if ! kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/legitimate-app-role >/dev/null 2>&1; then
    echo "📝 Création du rôle pour l'app légitime..."
    kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/legitimate-app-role \
      bound_service_account_names=legitimate-sa \
      bound_service_account_namespaces=legitimate-app \
      policies=legitimate-app-policy \
      ttl=1h
fi

if ! kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/malicious-app-role >/dev/null 2>&1; then
    echo "📝 Création du rôle MALVEILLANT pour l'app malveillante..."
    kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/malicious-app-role \
      bound_service_account_names=malicious-sa \
      bound_service_account_namespaces=malicious-app \
      policies=malicious-app-policy \
      ttl=1h
fi

echo "✅ Rôles Kubernetes configurés"

# Déployer les applications via ArgoCD
echo "🚀 Déploiement des applications via ArgoCD..."
echo "📦 Déploiement de l'application légitime..."
kubectl apply -f scenarios/02-vault-agent/argocd-apps.yaml

echo "⏳ Attente de la synchronisation ArgoCD..."
sleep 30

# Vérifier le statut des applications ArgoCD
echo "📊 Statut des applications ArgoCD:"
kubectl get applications -n argocd

echo ""
echo "🔍 Détails des applications:"
echo "Application Légitime:"
kubectl describe application legitimate-app -n argocd | grep -E "(Status|Health|Sync Status)" || true

echo ""
echo "Application Malveillante:"
kubectl describe application malicious-app -n argocd | grep -E "(Status|Health|Sync Status)" || true

echo ""
echo "📊 Statut des pods:"
echo "Application Légitime:"
kubectl get pods -n legitimate-app
echo ""
echo "Application Malveillante:"
kubectl get pods -n malicious-app

echo ""
echo "🎯 DÉMONSTRATION DE SÉCURITÉ PRÊTE !"
echo ""
echo "🌐 Accès à l'interface ArgoCD:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  # Ouvrir https://localhost:8080 dans le navigateur"
echo "  # Login: admin"
echo "  # Mot de passe: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo ""
echo "🎭 Pour démontrer l'attaque:"
echo "  # Vérifier les logs de l'app malveillante"
echo "  kubectl logs -n malicious-app deployment/malicious-app -c app"
echo ""
echo "  # Tester l'API de l'app malveillante (expose les secrets volés)"
echo "  kubectl port-forward svc/malicious-service -n malicious-app 8082:8080 &"
echo "  curl http://localhost:8082"
echo ""
echo "  # Tester l'API de l'app légitime"
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
echo "🧹 Pour nettoyer:"
echo "  kubectl delete -f scenarios/02-vault-agent/argocd-apps.yaml"
echo "  kubectl exec -n vault vault-0 -- vault kv delete secret/legitimate-app/config"
echo "  kubectl exec -n vault vault-0 -- vault kv delete secret/malicious-app/config"
echo "  kubectl exec -n vault vault-0 -- vault policy delete malicious-app-policy"
echo "  kubectl exec -n vault vault-0 -- vault policy delete legitimate-app-policy" 