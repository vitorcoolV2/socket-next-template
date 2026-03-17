#!/bin/bash
# --- _9-nuke-and-rebuild.sh ---
# O objetivo deste script é a reconstrução total e automatizada.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 0. Load env & Steward tools
. $(realpath ../.env)

docker exec -u 0 -it authentik-worker bash -c "
apt-get update && apt-get install -y netcat-openbsd dnsutils"

docker exec -u 0 -it authentik-server bash -c "
apt-get update && apt-get install -y netcat-openbsd dnsutils"

docker exec -it authentik-worker nc -zv mailcrab 1025

docker exec -i authentik-server ak shell <<EOF
from django.core.mail import send_mail
print("A tentar enviar...")
send_mail('Teste', 'Funciona!', 'vitor@home2500.local', ['test@test.com'], fail_silently=False)
print("Sucesso!")
EOF


docker exec -i authentik-worker ak shell <<EOF
from django.core.mail import send_mail
print("A tentar enviar...")
send_mail('Teste', 'Funciona!', 'vitor@home2500.local', ['test@test.com'], fail_silently=False)
print("Sucesso!")
EOF

docker exec -i authentik-worker ak shell <<EOF
import os
print(f"HOST SMTP: {os.environ.get('AUTHENTIK_EMAIL__HOST')}")
EOF

docker exec -i authentik-worker ak shell <<EOF
from django.conf import settings
print(f"DJANGO HOST: {settings.EMAIL_HOST}")
print(f"DJANGO PORT: {settings.EMAIL_PORT}")
EOF