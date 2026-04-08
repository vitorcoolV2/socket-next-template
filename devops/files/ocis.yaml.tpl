token_manager:
  jwt_secret: "{{OCIS_JWT_SECRET}}"
  machine_auth_api_key: "{{OCIS_MACHINE_AUTH_API_KEY}}"
  system_user_api_key: "{{OCIS_SYSTEM_USER_API_KEY}}"
  transfer_secret: "{{OCIS_TRANSFER_SECRET}}"
  system_user_id: "{{OCIS_SYSTEM_USER_ID}}"
  admin_user_id: "{{OCIS_ADMIN_USER_ID}}"

graph:
  application:
    id: "{{OCIS_GRAPH_APPLICATION_ID}}"
  identity:
    ldap:
      bind_password: "{{OCIS_IDM_REVA_PASSWORD}}" # Unificado
  service_account:
    service_account_id: "{{OCIS_SERVICE_ACCOUNT_ID}}"
    service_account_secret: "{{OCIS_SERVICE_ACCOUNT_SECRET}}"

idp:
  ldap:
    bind_password: "{{OCIS_IDM_REVA_PASSWORD}}" # Unificado

idm:
  service_user_passwords:
    admin_password: "{{OCIS_IDM_ADMIN_PASSWORD}}"
    idm_password: "{{OCIS_IDM_IDM_PASSWORD}}"
    reva_password: "{{OCIS_IDM_REVA_PASSWORD}}"
    idp_password: "{{OCIS_IDM_IDP_PASSWORD}}"

proxy:
  oidc:
    insecure: true
  insecure_backends: true
  service_account:
    service_account_id: "{{OCIS_SERVICE_ACCOUNT_ID}}"
    service_account_secret: "{{OCIS_SERVICE_ACCOUNT_SECRET}}"

auth_bearer:
  auth_providers:
    oidc:
      insecure: true

users:
  drivers:
    ldap:
      bind_password: "{{OCIS_IDM_REVA_PASSWORD}}"

groups:
  drivers:
    ldap:
      bind_password: "{{OCIS_IDM_REVA_PASSWORD}}"

# Adicionado para evitar erro 500 no microserviço de settings
settings:
  service_account_ids:
    - "{{OCIS_SERVICE_ACCOUNT_ID}}"