#!/bin/bash

echo "🔒 Application des Mesures de Sécurisation"
echo "=========================================="

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 1. Sécurisation des Politiques Vault
echo ""
echo "🔐 1. Configuration des Politiques Vault Sécurisées"

# Politique pour static1
kubectl exec -n vault vault-0 -- vault policy write static1-policy-secure - <<EOF
path "secret/data/static1/*" {
  capabilities = ["read"]
}
path "secret/data/static2/*" {
  capabilities = ["deny"]
}
path "secret/data/legitimate-app/*" {
  capabilities = ["deny"]
}
path "secret/data/malicious-app/*" {
  capabilities = ["deny"]
}
EOF
print_status "Politique static1-policy-secure créée"

# Politique pour static2
kubectl exec -n vault vault-0 -- vault policy write static2-policy-secure - <<EOF
path "secret/data/static2/*" {
  capabilities = ["read"]
}
path "secret/data/static1/*" {
  capabilities = ["deny"]
}
path "secret/data/legitimate-app/*" {
  capabilities = ["deny"]
}
path "secret/data/malicious-app/*" {
  capabilities = ["deny"]
}
EOF
print_status "Politique static2-policy-secure créée"

# Politique pour l'app légitime
kubectl exec -n vault vault-0 -- vault policy write legitimate-app-policy-secure - <<EOF
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
}
path "secret/data/malicious-app/*" {
  capabilities = ["deny"]
}
path "secret/data/static*/*" {
  capabilities = ["deny"]
}
EOF
print_status "Politique legitimate-app-policy-secure créée"

# Politique pour l'app malveillante (restrictive)
kubectl exec -n vault vault-0 -- vault policy write malicious-app-policy-secure - <<EOF
path "secret/data/malicious-app/*" {
  capabilities = ["read"]
}
path "secret/data/legitimate-app/*" {
  capabilities = ["deny"]
}
path "secret/data/static*/*" {
  capabilities = ["deny"]
}
EOF
print_status "Politique malicious-app-policy-secure créée"

# 2. Mise à jour des Rôles Vault
echo ""
echo "🔑 2. Mise à jour des Rôles Vault"

# Rôle pour static1
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/static1-role-secure \
  bound_service_account_names=static1-sa \
  bound_service_account_namespaces=static1 \
  policies=static1-policy-secure \
  ttl=1h \
  max_ttl=2h
print_status "Rôle static1-role-secure mis à jour"

# Rôle pour static2
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/static2-role-secure \
  bound_service_account_names=static2-sa \
  bound_service_account_namespaces=static2 \
  policies=static2-policy-secure \
  ttl=1h \
  max_ttl=2h
print_status "Rôle static2-role-secure mis à jour"

# Rôle pour l'app légitime
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/legitimate-app-role-secure \
  bound_service_account_names=legitimate-sa \
  bound_service_account_namespaces=legitimate-app \
  policies=legitimate-app-policy-secure \
  ttl=1h \
  max_ttl=2h
print_status "Rôle legitimate-app-role-secure mis à jour"

# Rôle pour l'app malveillante (restrictif)
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/malicious-app-role-secure \
  bound_service_account_names=malicious-sa \
  bound_service_account_namespaces=malicious-app \
  policies=malicious-app-policy-secure \
  ttl=1h \
  max_ttl=2h
print_status "Rôle malicious-app-role-secure mis à jour"

# 3. Activation de l'Audit Vault
echo ""
echo "📊 3. Configuration de l'Audit Vault"

# Vérifier si l'audit est déjà activé
AUDIT_STATUS=$(kubectl exec -n vault vault-0 -- vault audit list 2>/dev/null | grep file || echo "not_enabled")

if [ "$AUDIT_STATUS" = "not_enabled" ]; then
    kubectl exec -n vault vault-0 -- vault audit enable file file_path=/vault/logs/audit.log log_raw=true
    print_status "Audit Vault activé"
else
    print_warning "Audit Vault déjà activé"
fi

# 4. Network Policies
echo ""
echo "🌐 4. Application des Network Policies"

# Network Policy pour static1
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: static1-network-policy-secure
  namespace: static1
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: static1
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: vault
    ports:
    - protocol: TCP
      port: 8200
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF
print_status "Network Policy pour static1 appliquée"

# Network Policy pour static2
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: static2-network-policy-secure
  namespace: static2
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: static2
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: vault
    ports:
    - protocol: TCP
      port: 8200
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF
print_status "Network Policy pour static2 appliquée"

# 5. RBAC Strict
echo ""
echo "🔐 5. Configuration RBAC Strict"

# RBAC pour static1
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: static1-role-secure
  namespace: static1
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
  resourceNames: ["static1-config"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: static1-role-binding-secure
  namespace: static1
subjects:
- kind: ServiceAccount
  name: static1-sa
  namespace: static1
roleRef:
  kind: Role
  name: static1-role-secure
  apiGroup: rbac.authorization.k8s.io
EOF
print_status "RBAC pour static1 configuré"

# RBAC pour static2
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: static2-role-secure
  namespace: static2
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
  resourceNames: ["static2-config"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: static2-role-binding-secure
  namespace: static2
subjects:
- kind: ServiceAccount
  name: static2-sa
  namespace: static2
roleRef:
  kind: Role
  name: static2-role-secure
  apiGroup: rbac.authorization.k8s.io
EOF
print_status "RBAC pour static2 configuré"

# 6. Vérification de la Sécurisation
echo ""
echo "🔍 6. Vérification de la Sécurisation"

# Vérifier les politiques
echo "Politiques Vault créées :"
kubectl exec -n vault vault-0 -- vault policy list | grep -E "(static|legitimate|malicious).*-secure"

# Vérifier les rôles
echo ""
echo "Rôles Vault mis à jour :"
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/static1-role-secure

# Vérifier les Network Policies
echo ""
echo "Network Policies appliquées :"
kubectl get networkpolicies --all-namespaces | grep -E "(static1|static2).*-secure"

# Vérifier l'audit
echo ""
echo "Status de l'audit Vault :"
kubectl exec -n vault vault-0 -- vault audit list

echo ""
echo "🎉 Sécurisation terminée !"
echo ""
echo "📋 Prochaines étapes :"
echo "1. Tester les accès refusés :"
echo "   kubectl exec -n static2 static2-pod -- vault read secret/data/static1/config"
echo ""
echo "2. Surveiller les logs d'audit :"
echo "   kubectl logs -n vault vault-0 | grep -E '(unauthorized|denied)'"
echo ""
echo "3. Vérifier les Network Policies :"
echo "   kubectl describe networkpolicy -n static1 static1-network-policy-secure"
echo ""
echo "4. Tester la rotation des secrets :"
echo "   ./rotate-secrets.sh" 