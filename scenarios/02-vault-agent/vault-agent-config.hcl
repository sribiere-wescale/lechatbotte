    pid_file = "/home/vault/pidfile"

    listener "tcp" {
      address     = "127.0.0.1:8200"
      tls_disable = true
    }

    auto_auth {
      method "kubernetes" {
        mount_path = "auth/kubernetes"
        config = {
          role = "legitimate-app-role"
        }
      }
    }

    template {
      destination = "/vault/secrets/legitimate-config"
      contents = "username={{ with secret \"secret/data/legitimate-app/config\" }}{{ .Data.data.username }}{{ end }}\npassword={{ with secret \"secret/data/legitimate-app/config\" }}{{ .Data.data.password }}{{ end }}\napi_key={{ with secret \"secret/data/legitimate-app/config\" }}{{ .Data.data.apikey }}{{ end }}\ndatabase_url={{ with secret \"secret/data/legitimate-app/config\" }}{{ .Data.data.databaseurl }}{{ end }}"
    }

    vault {
      address = "http://vault.vault.svc.cluster.local:8200"
    }

    cache {
      use_auto_auth_token = true
    }