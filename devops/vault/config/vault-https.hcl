# vault/config/vault.hcl
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:443"  
  tls_disable   = 0
  tls_cert_file = "/vault/config/certs/vault-fullchain.crt"
  tls_key_file  = "/vault/config/certs/vault.key"
}

api_addr = "https://172.28.0.6:443"
ui = true
disable_mlock = true