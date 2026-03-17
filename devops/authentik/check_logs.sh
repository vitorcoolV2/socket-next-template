#!/bin/bash

echo "=== A recolher logs do Authentik (Erros de Flow e Captcha) ==="

# 1. Procura por erros de Captcha (Invalid Challenge)
echo "--- Erros de Captcha/Challenge ---"
docker compose logs server | grep -i "Invalid challenge" | grep "captcha_stage"

# 2. Procura por conflitos de planos (O que causa o loop de voltar ao e-mail)
echo -e "\n--- Conflitos de Sessão/Flow Plans ---"
docker compose logs server | grep -i "Found existing plan for other flow"

# 3. Verifica se o Email Stage está a disparar corretamente para o MailCrab
echo -e "\n--- Atividade do Email Stage ---"
docker compose logs worker | grep -i "Sending mail"

# 4. Procura por erros de aplicação de Blueprints
echo -e "\n--- Erros de Blueprints ---"
docker compose logs server | grep -i "blueprint" | grep -i "error"