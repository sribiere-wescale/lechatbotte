# Guide de Sécurisation - Combler les Fuites de Secrets

## 🎯 Objectif

Ce guide démontre comment sécuriser les déploiements pour éviter le vol de secrets identifié dans les scénarios de démonstration.

## 🔒 Scénario 1 : Sécurisation des Secrets Statiques

### ❌ Problème Identifié
L'application `static2` peut accéder aux secrets de `static1` via le ServiceAccount avec des droits trop larges.

### ✅ Solution : Politiques Vault Strictes

#### 1. Créer des Politiques Vault Restrictives
```bash
# Politique pour static1 - accès uniquement à ses propres secrets
kubectl exec -n vault vault-0 -- vault policy write static1-policy - <<EOF
path "secret/data/static1/*" {
  capabilities = ["read"]
}
EOF

# Politique pour static2 - accès uniquement à ses propres secrets
kubectl exec -n vault vault-0 -- vault policy write static2-policy - <<EOF
path "secret/data/static2/*" {
  capabilities = ["read"]
}
EOF
```

#### 2. Rôles Vault avec Binding Strict
```bash
# Rôle pour static1 - lié uniquement à son ServiceAccount
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/static1-role \
  bound_service_account_names=static1-sa \
  bound_service_account_namespaces=static1 \
  policies=static1-policy \
  ttl=1h

# Rôle pour static2 - lié uniquement à son ServiceAccount
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/static2-role \
  bound_service_account_names=static2-sa \
  bound_service_account_namespaces=static2 \
  policies=static2-policy \
  ttl=1h
```

#### 3. Network Policies pour Isolation Réseau
```yaml
# network-policy-static1.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: static1-network-policy
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
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: vault
    ports:
    - protocol: TCP
      port: 8200
```

## 🔒 Scénario 2 : Sécurisation de Vault Agent

### ❌ Problème Identifié
L'application malveillante utilise des templates Vault Agent pour accéder aux secrets d'autres applications.

### ✅ Solution : Contrôle d'Accès Granulaire

#### 1. Politiques Vault avec Chemins Spécifiques
```bash
# Politique pour l'app légitime - accès uniquement à ses secrets
kubectl exec -n vault vault-0 -- vault policy write legitimate-app-policy - <<EOF
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
}
# Interdire l'accès aux secrets d'autres applications
path "secret/data/malicious-app/*" {
  capabilities = ["deny"]
}
path "secret/data/static*/*" {
  capabilities = ["deny"]
}
EOF

# Politique pour l'app malveillante - accès uniquement à ses secrets
kubectl exec -n vault vault-0 -- vault policy write malicious-app-policy - <<EOF
path "secret/data/malicious-app/*" {
  capabilities = ["read"]
}
# Interdire l'accès aux secrets d'autres applications
path "secret/data/legitimate-app/*" {
  capabilities = ["deny"]
}
path "secret/data/static*/*" {
  capabilities = ["deny"]
}
EOF
```

#### 2. Validation des Templates Vault Agent
```hcl
# vault-agent-config-secure.hcl
template {
  destination = "/vault/secrets/legitimate-config"
  # Validation stricte - uniquement les chemins autorisés
  contents = <<EOH
{{- if eq .Path "secret/data/legitimate-app/config" }}
username={{ with secret "secret/data/legitimate-app/config" }}{{ .Data.data.username }}{{ end }}
password={{ with secret "secret/data/legitimate-app/config" }}{{ .Data.data.password }}{{ end }}
{{- else }}
# Accès refusé
{{- end }}
EOH
}
```

#### 3. Audit et Monitoring
```bash
# Activer l'audit dans Vault
kubectl exec -n vault vault-0 -- vault audit enable file file_path=/vault/logs/audit.log

# Surveiller les accès aux secrets
kubectl exec -n vault vault-0 -- vault audit list
```

## 🔒 Scénario 3 : Sécurisation de Vault Secrets Operator

### ❌ Problème Identifié
L'application malveillante crée des VaultDynamicSecrets pour accéder aux secrets d'autres applications.

### ✅ Solution : Contrôle d'Accès au Niveau Kubernetes

#### 1. RBAC Strict pour VSO
```yaml
# rbac-vso-secure.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vso-legitimate-app-role
rules:
- apiGroups: ["secrets.hashicorp.com"]
  resources: ["vaultdynamicsecrets"]
  verbs: ["get", "list", "watch"]
  resourceNames: ["legitimate-secrets"]  # Seulement son propre secret
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vso-legitimate-app-binding
subjects:
- kind: ServiceAccount
  name: legitimate-sa
  namespace: legitimate-app
roleRef:
  kind: ClusterRole
  name: vso-legitimate-app-role
  apiGroup: rbac.authorization.k8s.io
```

#### 2. Admission Controller pour VaultDynamicSecrets
```yaml
# admission-webhook-vso.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: vso-secret-validation
webhooks:
- name: vso.secrets.hashicorp.com
  rules:
  - apiGroups: ["secrets.hashicorp.com"]
    apiVersions: ["v1beta1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["vaultdynamicsecrets"]
  clientConfig:
    service:
      namespace: vault
      name: vso-admission-webhook
      path: "/validate-vaultdynamicsecrets"
  admissionReviewVersions: ["v1"]
```

#### 3. Politiques Vault avec Validation de Namespace
```bash
# Politique avec validation de namespace
kubectl exec -n vault vault-0 -- vault policy write legitimate-app-policy-secure - <<EOF
# Vérifier que l'application accède uniquement à ses propres secrets
path "secret/data/legitimate-app/*" {
  capabilities = ["read"]
  # Validation que le namespace correspond
  required_parameters = ["namespace"]
  allowed_parameters = {
    "namespace" = ["legitimate-app"]
  }
}
EOF
```

## 🔒 Mesures Générales de Sécurisation

### 1. Network Policies
```yaml
# network-policy-default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: legitimate-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  # Par défaut, tout est refusé
  ingress: []
  egress: []
```

### 2. Pod Security Standards
```yaml
# pod-security.yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

### 3. Secrets Rotation Automatique
```bash
# Script de rotation des secrets
#!/bin/bash
# rotate-secrets.sh
kubectl exec -n vault vault-0 -- vault kv put secret/legitimate-app/config \
  username="legitimate_user_$(date +%s)" \
  password="$(openssl rand -base64 32)" \
  apikey="$(openssl rand -hex 32)" \
  databaseurl="postgresql://legitimate-db:5432/legitimate_db"
```

### 4. Monitoring et Alerting
```yaml
# monitoring-vault.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'vault'
      static_configs:
      - targets: ['vault.vault.svc.cluster.local:8200']
      metrics_path: '/v1/sys/metrics'
      params:
        format: ['prometheus']
```

## 🔍 Détection d'Intrusion

### 1. Logs Vault Centralisés
```bash
# Configuration des logs Vault
kubectl exec -n vault vault-0 -- vault audit enable file file_path=/vault/logs/audit.log log_raw=true

# Surveillance des accès suspects
kubectl logs -n vault vault-0 | grep -E "(unauthorized|denied|failed)"
```

### 2. Alertes sur Accès Anormaux
```yaml
# alert-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: vault-security-alerts
spec:
  groups:
  - name: vault.security
    rules:
    - alert: VaultUnauthorizedAccess
      expr: vault_core_unsealed == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Accès non autorisé détecté dans Vault"
```

### 3. Audit des VaultDynamicSecrets
```bash
# Script d'audit des VaultDynamicSecrets
#!/bin/bash
# audit-vso.sh
echo "=== Audit des VaultDynamicSecrets ==="
kubectl get vaultdynamicsecrets --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,PATH:.spec.path" | grep -v "NAMESPACE"
```

## 📋 Checklist de Sécurisation

### ✅ Avant Déploiement
- [ ] Politiques Vault restrictives configurées
- [ ] Rôles Vault avec binding strict
- [ ] Network Policies appliquées
- [ ] RBAC configuré pour VSO
- [ ] Admission Controllers activés

### ✅ Monitoring Continu
- [ ] Logs Vault centralisés
- [ ] Alertes configurées
- [ ] Audit des accès régulier
- [ ] Rotation des secrets automatique

### ✅ Tests de Sécurité
- [ ] Tests de pénétration des politiques
- [ ] Validation des accès refusés
- [ ] Tests de contournement
- [ ] Validation des alertes

## 🚨 Réponse aux Incidents

### 1. Détection d'Accès Non Autorisé
```bash
# Isoler l'application suspecte
kubectl scale deployment malicious-app -n malicious-app --replicas=0

# Révoquer les tokens Vault
kubectl exec -n vault vault-0 -- vault token revoke -self

# Analyser les logs
kubectl logs -n vault vault-0 --since=1h | grep -E "(unauthorized|denied)"
```

### 2. Rotation d'Urgence
```bash
# Rotation immédiate des secrets compromis
kubectl exec -n vault vault-0 -- vault kv put secret/legitimate-app/config \
  username="emergency_user_$(date +%s)" \
  password="$(openssl rand -base64 32)" \
  apikey="$(openssl rand -hex 32)"
```

### 3. Investigation
```bash
# Collecter les logs d'audit
kubectl exec -n vault vault-0 -- cat /vault/logs/audit.log | grep "$(date +%Y-%m-%d)"

# Analyser les VaultDynamicSecrets
kubectl get vaultdynamicsecrets --all-namespaces -o yaml
```

Ce guide fournit une approche complète pour sécuriser les déploiements et éviter les fuites de secrets identifiées dans les démonstrations. 