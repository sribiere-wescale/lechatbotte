pid_file = "/home/vault/pidfile"

auto_auth {
  method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
      role = "vault-agent-demo"
    }
  }
}

template {
  destination = "/vault/secrets/config"
  contents = <<EOH
{{- with secret "secret/data/vault-agent/config" }}
username={{ .Data.data.username }}
password={{ .Data.data.password }}
api_key={{ .Data.data.api-key }}
{{- end }}
EOH
}

vault {
  address = "http://vault.vault.svc.cluster.local:8200"
}

cache {
  use_auto_auth_token = true
} 