#!/bin/bash
# --- _2-rotate-oidc-vault.sh ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -e
. $(realpath ../authentik/_0-authentik_lib.sh)
set +e


# 1. Load enable oidc provider environment
require_vars "AUTENTIK_OIDC_VAULT_STEWARD_ROLE" || exit
require_vars "CURL_CA_OPTS" "VAULT_CACERT" "DOMAIN" \
        "AUTHENTIK_API_TOKEN" \
        "AUTHENTIK_ADMIN_USER" || exit

for f in  check_well_known_openid_config; do ! declare -F "$f" >/dev/null && echo "❌ Function $f not found" && exit 1; done


if ! check_well_known_openid_config 2; then    
    echo "❌ Error: OIDC well-known configuration not ready"
    return 1
fi

#### >>>>>>>>>>>>>>>>>>>>>>>>>>>> THE RECOVERY FLOW >>>>>>>>>>>>>>>>>>>
#### authentik vanila does not come with recovery flow,
###  so setup>>> home2500 recovery flow
RECOVERY_FLOW_SLUG="home2500-recovery-flow"
echo "🚀 [Flow:$RECOVERY_FLOW_SLUG]"

RECOVERY_FLOW_JSON_CONTENT=$(cat <<EOF
{
    "name": "Password Recovery Flow",
    "slug": "$RECOVERY_FLOW_SLUG",
    "designation": "recovery",
    "title": "Home2500 Reset your password",
    "compatibility_mode": true
}
EOF
)
#echo "$RECOVERY_FLOW_JSON_CONTENT" | jq

RECOVERY_FLOW_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/flows/instances/?slug=$RECOVERY_FLOW_SLUG" | \
        jq -r '.results[0].pk')
# Logic to determine URL and Method
if [ -z "$RECOVERY_FLOW_PK" ] || [ "$RECOVERY_FLOW_PK" == "null" ]; then
    echo "🏗️  Flow not found. Creating..."
    _method="POST"
    # POST goes to the collection root
    _url="https://auth.$DOMAIN/api/v3/flows/instances/"
else
    echo "⚙️  Flow found (PK: $RECOVERY_FLOW_PK). Updating via Slug..."
    _method="PATCH"
    # PATCH works best using the SLUG in the URL path for flows
    _url="https://auth.$DOMAIN/api/v3/flows/instances/$RECOVERY_FLOW_SLUG/"
fi

# Execute and Format Output
echo "$_method $_url"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$RECOVERY_FLOW_JSON_CONTENT")
# Display Result as "Name: PK"
RECOVERY_FLOW_PK=$(echo "$RESPONSE" | jq -r '.pk')
#report
echo "$RESPONSE" | jq .
echo "Flow: $RECOVERY_FLOW_SLUG: $RECOVERY_FLOW_PK"


# selecting the service to validate user, before let reset password.
# Extremly important on crawded places, home2500 is private let relax, 
# 
# mailcrab is authentik private now manual, but i intent @TODO other feature make automation send externalEmail(user@home2500.local)
# and only all "email/link/...other id contents"..
# can email with link to reset password have i report tech session about requester ip,tls, issuer, y know security check ids
#  will be submited to ...
# >>>>>>>>>>>>>>>>>>>>>>>>>>> stage EMAIL >>>>>>>
echo "📧 [Stage: email]"
EMAIL_STAGE_NAME="home2500-mailcrap-service"

# Configuration for your SMTP
SMTP_HOST="mailcrab.app-network"
SMTP_PORT=1025
FROM_ADDRESS="authentik@home2500.local"

# Define the JSON content (removed == and quotes from port)
MAILCRAB_JSON_CONTENT=$(cat <<EOF
{
    "name": "$EMAIL_STAGE_NAME",
    "host": "$SMTP_HOST",
    "port": $SMTP_PORT,
    "username": "",
    "password": "",
    "use_tls": false,
    "use_ssl": false,
    "from_address": "$FROM_ADDRESS",
    "subject": "Home2500 Recovery Link",
    "template": "email/password_reset.html",
    "activate_user_on_success": true,
    "token_expiry": 30
}
EOF
)

# Fetch PK (ensuring we handle multiple results by taking the first one)
EMAIL_STAGE_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/stages/email/?name=$EMAIL_STAGE_NAME" | jq -r '.results[0].pk // empty')

# Logic to determine URL and Method
if [ -z "$EMAIL_STAGE_PK" ] || [ "$EMAIL_STAGE_PK" == "null" ]; then
    echo "🏗️  Stage not found. Creating..."
    _method="POST"
    _url="https://auth.$DOMAIN/api/v3/stages/email/"
else
    echo "⚙️  [email: $EMAIL_STAGE_NAME] Applying PATCH to PK: $EMAIL_STAGE_PK"
    _method="PATCH"
    _url="https://auth.$DOMAIN/api/v3/stages/email/$EMAIL_STAGE_PK/"
fi

# Execute and Format Output
echo "$_method $_url"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$MAILCRAB_JSON_CONTENT")

#report
EMAIL_STAGE_PK=$(echo "$RESPONSE" | jq -r '.pk // empty')
echo "$RESPONSE" | jq .
echo "Stage: email: $EMAIL_STAGE_NAME: $EMAIL_STAGE_PK"

# >>>>>>>>>>>>>>>>>>>>>>>>>>> stage PASSWORD >>>>>>>
echo "📧 [Stage: password]"
PW_STAGE_NAME="home2500-recovery-password-input"
PW_STAGE_BACKEND="authentik.core.auth.InbuiltBackend"
# Fetch PK (ensuring we handle multiple results by taking the first one)
PW_STAGE_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/stages/password/?name=$PW_STAGE_NAME" | jq -r '.results[0].pk // empty')

# Define the JSON content (removed == and quotes from port)
PW_JSON_CONTENT=$(cat <<EOF
{
    "name": "$PW_STAGE_NAME",
    "backends": ["$PW_STAGE_BACKEND"],
    "configure_flow": null,
    "failed_attempts_before_cancel": 5,
    "password_confirmation": true,
    "configure_flow": null    
}
EOF
)    
## "configure_flow": "$RECOVERY_FLOW_PK" seams t be a mistake


# Logic to determine URL and Method
if [ -z "$PW_STAGE_PK" ] || [ "$PW_STAGE_PK" == "null" ]; then
    echo "🏗️  Stage not found. Creating..."
    _method="POST"
    _url="https://auth.$DOMAIN/api/v3/stages/password/"
else
    echo "⚙️  [password: $PW_STAGE_NAME] Applying PATCH to PK: $PW_STAGE_PK"
    _method="PATCH"
    _url="https://auth.$DOMAIN/api/v3/stages/password/$PW_STAGE_PK/"
fi

# Execute and Format Output
echo "$_method $_url"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PW_JSON_CONTENT")

#report
PW_STAGE_PK=$(echo "$RESPONSE" | jq -r '.pk // empty')
echo "$RESPONSE" | jq .
echo "Stage: password: $PW_STAGE_NAME: $PW_STAGE_PK"

# >>>>>>>>>>>>>>>>>>>>>>>>>>> stage USER WRITE >>>>>>>
echo "📧 [Stage: user-write]"
WRITE_STAGE_NAME="home2500-recovery-user-write"

# Define the JSON content (removed == and quotes from port)
WRITE_JSON_CONTENT=$(cat <<EOF
{
    "name": "$WRITE_STAGE_NAME",
    "create_users_as_inactive": false,
    "user_creation_mode": "never_create",
    "create_users_group": null,
    "user_path_template": ""
}
EOF
)

# Fetch PK (ensuring we handle multiple results by taking the first one)
WRITE_STAGE_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/stages/user_write/?name=$WRITE_STAGE_NAME" | jq -r '.results[0].pk // empty')

# Logic to determine URL and Method
if [ -z "$WRITE_STAGE_PK" ] || [ "$WRITE_STAGE_PK" == "null" ]; then
    echo "🏗️  Stage not found. Creating..."
    _method="POST"
    _url="https://auth.$DOMAIN/api/v3/stages/user_write/"
else
    echo "⚙️  [user-write: $WRITE_STAGE_NAME] Applying PATCH to PK: $WRITE_STAGE_PK"
    _method="PATCH"
    _url="https://auth.$DOMAIN/api/v3/stages/user_write/$WRITE_STAGE_PK/"
fi

# Execute and Format Output
echo "$_method $_url"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$WRITE_JSON_CONTENT")

#report
WRITE_STAGE_PK=$(echo "$RESPONSE" | jq -r '.pk // empty')
echo "$RESPONSE" | jq .
echo "Stage: user-write: $WRITE_STAGE_NAME: $WRITE_STAGE_PK"

for v in WRITE_STAGE_PK ; do [ -z "${!v}" ] && echo "❌ Env Var $v is empty" && exit 1; done

# >>>>>>>>>>>>>>>>>>> STAGE IDENTIFICATION
echo "📧 [Stage: identification]"
ID_STAGE_NAME="home2500-recovery-identification"
ID_STAGE_JSON_CONTENT=$(cat <<EOF
{
    "name": "$ID_STAGE_NAME",
    "password_recovery_flow": "$RECOVERY_FLOW_PK",
    "user_fields": ["username", "email"],
    "captcha_stage": null,
    "password_stage": null,
    "pretend_user_exists": true,
    "case_insensitive_matching": true,
    "show_matched_user": true
}
EOF
)

ID_STAGE_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/stages/identification/?name=$ID_STAGE_NAME" | jq -r '.results[0].pk // empty')

# Logic to determine URL and Method
if [ -z "$ID_STAGE_PK" ]; then
    echo "🏗️  Stage not found. Creating..."
    _method="POST"
    _url="https://auth.$DOMAIN/api/v3/stages/identification/"
else
    echo "⚙️  [identification: $ID_STAGE_NAME] Applying PATCH to PK: $ID_STAGE_PK"
    _method="PATCH"
    _url="https://auth.$DOMAIN/api/v3/stages/identification/$ID_STAGE_PK/"
fi

# Execute and Format Output
echo "$_method $_url"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$ID_STAGE_JSON_CONTENT")

#report
ID_STAGE_PK=$(echo "$RESPONSE" | jq -r '.pk // empty')
echo "$RESPONSE" | jq .
echo "Stage: identification: $ID_STAGE_NAME: $ID_STAGE_PK"

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> Inventory Flow/stages  >>>>>>>>
echo ""
echo "📋 [Summary] IDs Obtained:"
echo "   Flow >> $RECOVERY_FLOW_SLUG >>  $RECOVERY_FLOW_PK"
echo "   - Id       > $ID_STAGE_NAME    > $ID_STAGE_PK"
echo "   - Email    > $EMAIL_STAGE_NAME > $EMAIL_STAGE_PK"
echo "   - Password > $PW_STAGE_NAME    > $PW_STAGE_PK"
echo "   - Write    > $WRITE_STAGE_NAME > $WRITE_STAGE_PK"

# >>>>>>>> VALIDATE BINDING VALUE REQUIREMENTS   >>>>>>>>
# exit if missing *_FLOW_* && *_STAGE_* vars
# check required values
for v in RECOVERY_FLOW_PK EMAIL_STAGE_PK PW_STAGE_PK WRITE_STAGE_PK ID_STAGE_PK ;  \
    do [ -z "${!v}" ] && echo "❌ Env Var $v is empty" && exit 1; done


# >>>>>>>> DELETE PREVIOUS BINDINGS >>>>>
echo ""
echo "🧹 [Binding] Cleaning existing Flow: $RECOVERY_FLOW_PK, stages bindings..."
EXISTING_BINDINGS=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/flows/bindings/?target=$RECOVERY_FLOW_PK" | jq -r '.results[].pk')
for B_PK in $EXISTING_BINDINGS; do
    curl -s -k -X DELETE "https://auth.$DOMAIN/api/v3/flows/bindings/$B_PK/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN"
done

# >>>>>>>>> APPLY BINDINGS
apply_binding() {
    local STAGE_PK=$1
    local ORDER=$2
    local evaluate_on_plan=${3,"false"}
    local _CONTENT=$(cat <<EOF
{
    "target": "$RECOVERY_FLOW_PK",
    "stage": "$STAGE_PK",
    "order": $ORDER,
    "evaluate_on_plan": $evaluate_on_plan
}
EOF
)
    echo "⛓️   Binding at Order $ORDER the Stage $STAGE_ID..."
    echo "POST "https://auth.$DOMAIN/api/v3/flows/bindings/""
    RESPONSE=$(curl -s -k -X POST "https://auth.$DOMAIN/api/v3/flows/bindings/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$_CONTENT")
    echo "$RESPONSE" | jq 
    # '.order"   Binding Result Order \(.order):  .\(.pk // "Error")"'
}

# ORDERED Array of Stage PKs in order: Id > Email -> Password -> User Write
# 2. Loop and bind
echo "🔗 [Binding] Applying bindings of flow slub: $RECOVERY_FLOW_SLUG, pk: $RECOVERY_FLOW_PK"

apply_binding "$ID_STAGE_PK"    0   true
apply_binding "$EMAIL_STAGE_PK" 10
apply_binding "$PW_STAGE_PK"    20
apply_binding "$WRITE_STAGE_PK" 30


# >>>>>>>>>>>>>>>>>>>>>>>>> DISABLE CURRENT BRAND, ENABLE BRANDed BRAND
# require disable current brand, to enable home2500

# Get PK and Patch 'default' to true in one pipe
# >>>>> DISABLE CURRENT
# 1. IDENTIFY: Get Default Brand and Home2500 Brand PKs


echo "📧 [Brand: $DOMAIN]"
CURRENT_DEFAULT_PK=$(curl -skH "Authorization: Bearer $AUTHENTIK_API_TOKEN" "https://auth.$DOMAIN/api/v3/core/brands/?default=true" | jq -r '.results[0].brand_uuid // empty')
HOME_BRAND_PK=$(curl -skH "Authorization: Bearer $AUTHENTIK_API_TOKEN" "https://auth.$DOMAIN/api/v3/core/brands/?domain=$DOMAIN" | jq -r '.results[0].brand_uuid // empty')


# 2. DISABLE: Remove default status from the old brand if it's not our target
if [ -n "$CURRENT_DEFAULT_PK" ] && [ "$CURRENT_DEFAULT_PK" != "$HOME_BRAND_PK" ]; then
    echo "⚠️ Disabling current default brand: $CURRENT_DEFAULT_PK"
    curl -skX PATCH "https://auth.$DOMAIN/api/v3/core/brands/$CURRENT_DEFAULT_PK/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" -H "Content-Type: application/json" \
        -d '{"default": false}' | jq -c '.domain'
fi

# 3. ENABLE/CREATE: Set home2500 as default and link recovery
if [ -z "$HOME_BRAND_PK" ]; then
    echo "🏗️ Brand not found. Creating..."
    _method="POST"; _url="https://auth.$DOMAIN/api/v3/core/brands/"
else
    echo "⚙️ [Brand: $DOMAIN] Enabling and Linking Recovery to: $HOME_BRAND_PK"
    _method="PATCH"; _url="https://auth.$DOMAIN/api/v3/core/brands/$HOME_BRAND_PK/"
fi

# 5. Prepare JSON Content
BNAME="Home2500"
BRAND_JSON_CONTENT=$(cat <<EOF
{
    "domain": "$DOMAIN",
    "flow_recovery": "$RECOVERY_FLOW_PK",
    "branding_title": "$BNAME Recovery",
    "default": true
}
EOF
)

# 6. Execute and Format Output
echo "$_method $_url -d $BRAND_JSON_CONTENT"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BRAND_JSON_CONTENT")

# 6. Report
HOME_BRAND_PK=$(echo "$RESPONSE" | jq -r '.pk // empty')
echo "$RESPONSE" | jq .
echo "$RESPONSE" | jq -r '"Brand updated: " + .domain + " (Recovery Flow: " + .flow_recovery + ")"'


# >>>>>>>>>>>>>>>>>>>>>>>> DEFINE (free) POLICY EXPRESSION >>>>>>>>>>

# 1. Check if the Expression Policy already exists
POLICY_NAME="home2500-recovery-skip-identification-if-token"
echo "📧 [Policy expression: $POLICY_NAME]"
POLICY_PK=$(curl -sk -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/policies/expression/?name=$POLICY_NAME" | jq -r '.results[0].pk // empty')

if [ -z "$POLICY_PK" ]; then
    echo "🏗️ Policy expression not found. Creating..."
    _method="POST"
    _url="https://auth.$DOMAIN/api/v3/policies/expression/"
else
    echo "⚙️  [Policy expression: $POLICY_NAME] Applying PATCH to PK: $POLICY_PK"
    _method="PATCH"
    _url="https://auth.$DOMAIN/api/v3/policies/expression/$POLICY_PK/"
fi

# This returns False (skipping the stage) if 'flow_token' is found in the URL
SKIP_POLICY_JSON_CONTENT=$(cat <<EOF
{
    "name": "$POLICY_NAME",
    "expression": "return \"flow_token\" not in request.http_request.GET"    
}
EOF
)
#"expression": "return 'flow_token' not in request.context.get('args', {})"
# Policy Creation/Update
echo "$_method $_url"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SKIP_POLICY_JSON_CONTENT" | jq .)


POLICY_PK=$(echo "$RESPONSE" | jq -r '.pk // empty')
echo "$RESPONSE" | jq .
echo "Policy expression: $POLICY_NAME, PK: $POLICY_PK"

# >>>>>>>>>>>>>>>>>> ENBLE FLOW STAGE IDENTIFICATION POLICY
# Find the binding ID for the Identification stage (Order 0) in your recovery flow
echo "📧 [binding $RECOVERY_FLOW_SLUG (0): flows/bindings/?target=$RECOVERY_FLOW_PK&order=0 ]"
ID_STG_BINDING=$(curl -skH "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/flows/bindings/?target=$RECOVERY_FLOW_PK&order=0"\
     | jq -r '.')
echo "$ID_STG_BINDING" | jq .    
ID_STG_BINDING_PK=$(echo "$ID_STG_BINDING" | jq -r '.results[0].pk')     

#echo "$SKIP_BINDING_JSON_CONTENT" | jq .
# 2. Find the ACTUAL Policy Binding PK (not the stage binding)
echo "---context"

echo "auth.$DOMAIN/api/v3/policies/bindings/?stage=$ID_STG_BINDING_PK"
curl -skH "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/policies/bindings/?stage=$ID_STG_BINDING_PK&order=0" | \
    jq #'.results[] | {order: .order, pk: .pk, target: .target, stage: .stage, evaluate_on_plan: .evaluate_on_plan, re_evaluate_policies: .re_evaluate_policies, stage_name: .stage_obj.name, stage_type: .stage_obj.verbose_name}' 
echo "----context end"  
POL_BIND_PK=$(curl -skH "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/policies/bindings/?stage=$ID_STG_BINDING_PK&policy=$POLICY_PK" | jq -r '.results[0].pk // empty')


# 3. Define the Correct Payload
# The 'target' inside the JSON is correct (it points to the stage binding)
SKIP_BINDING_JSON_CONTENT=$(cat <<EOF
{
    "target": "$ID_STG_BINDING_PK",
    "stage": "$ID_STAGE_PK",
    "policy": "$POLICY_PK",
    "order": 0,
    "timeout": 30,
    "enabled": true,    
    "evaluate_on_plan": true,
    "re_evaluate_policies": true,
    "enabled": true
}
EOF
)

if [ -z "$POL_BIND_PK" ] || [ "$POL_BIND_PK" == "null" ]; then
    echo "🏗️  Policy link not found. Creating via POST..."
    _method="POST"
    _url="https://auth.$DOMAIN/api/v3/policies/bindings/"
else
    echo "⚙️  Policy link found. Updating via PATCH to PK: $POL_BIND_PK"
    _method="PATCH"
    _url="https://auth.$DOMAIN/api/v3/policies/bindings/$POL_BIND_PK/"
fi
#echo "SKIP_BINDING_JSON_CONTENT="
#echo "$SKIP_BINDING_JSON_CONTENT" | jq .

#echo "----arguments end"   
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/flows/bindings/?target=$RECOVERY_FLOW_PK" | \
    jq '.results[] | {order: .order, pk: .pk, target: .target, stage: .stage, evaluate_on_plan: .evaluate_on_plan, re_evaluate_policies: .re_evaluate_policies, stage_name: .stage_obj.name, stage_type: .stage_obj.verbose_name}' 

# 4. Execute
echo "$_method $_url"
RESPONSE=$(curl -s -k -X "$_method" "$_url" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SKIP_BINDING_JSON_CONTENT" )

echo "$RESPONSE" | jq .
POL_BIND_PK=$(echo "$RESPONSE" | jq -r '.pk')
echo "Policy bind ( Policy expression, Flow Stage Bind) PK: $POL_BIND_PK "
echo " - Policy expression PK: $POLICY_PK"
echo " - Flow stage PK: $ID_STG_BINDING_PK"

echo "https://auth.$DOMAIN/api/v3/flows/bindings/?target=$RECOVERY_FLOW_PK"
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/flows/bindings/?target=$RECOVERY_FLOW_PK" | \
    jq '.results[] | {order: .order, pk: .pk, target: .target, stage: .stage, evaluate_on_plan: .evaluate_on_plan, re_evaluate_policies: .re_evaluate_policies, stage_name: .stage_obj.name, stage_type: .stage_obj.verbose_name}' 
echo "ID_STG_BINDING_PK=$ID_STG_BINDING_PK"
echo "POLICY_PK=$POLICY_PK"
echo "RECOVERY_FLOW_PK=$RECOVERY_FLOW_PK"
echo "ID_STAGE_PK=$ID_STAGE_PK"    
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/flows/bindings/?target=$RECOVERY_FLOW_PK" | jq '.results[]'   
  

# >>>>>>>> end


echo ""
echo "🏁 [Done] Starting Final Verification Tests..."
echo ""

### >>>>>>>>>>>>>>>>>>>>>>>>>> SEND EMAIL 7 - me first user
USER_PK="me"
echo "👤 [User] Checking data for User ID $USER_PK"
U="https://auth.$DOMAIN/api/v3/core/users/$USER_PK/"

# Fetch the object once
USER_O=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U")

# Extract fields (Since /users/7/ returns a single object, no .results[] is needed)
USER_PK=$(echo "$USER_O" | jq -r '.user.pk // "N/A"')
USER_USER_NAME=$(echo "$USER_O" | jq -r '.user.username // "N/A"')
USER_NAME=$(echo "$USER_O" | jq -r '.user.name // "N/A"')
USER_EMAIL=$(echo "$USER_O" | jq -r '.user.email // "N/A"')
USER_GROUPS=$(echo "$USER_O" | jq -r '.user.groups // "N/A"')
echo "--------------------------------------"
echo "USER PK:   $USER_PK"
echo "USERNAME: $USER_USER_NAME"
echo "NAME:     $USER_NAME"
echo "EMAIL:    $USER_EMAIL"
echo "GROUPS:    $USER_GROUPS"
echo "--------------------------------------"
# Check if email is missing (the cause of your 400 error)
if [ "$USER_EMAIL" == "N/A" ] || [ -z "$USER_EMAIL" ]; then
    echo "❌ ERROR: User has no email. 'Send Recovery Link' will fail."
else
    echo "✅ Email found. Recovery should work."
fi

REQUEST_RECOVER__JSON_CONTENT=$(cat <<EOF
{
    "identifier": "manual-test-$(date +%s)",
    "intent": "api",
    "user": $USER_PK,
    "expiring": true
}
EOF
)
# Create a manual Recovery Token
echo "POST https://auth.$DOMAIN/api/v3/core/tokens/"
echo "$REQUEST_RECOVER__JSON_CONTENT" | jq .
TOKEN_DATA=$(curl -s -k -X POST "https://auth.$DOMAIN/api/v3/core/tokens/" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_RECOVER__JSON_CONTENT")
echo "$TOKEN_DATA" | jq .
TOKEN_KEY=$(echo $TOKEN_DATA | jq -r '.key')

if [ "$TOKEN_KEY" != "null" ] && [ -n "$TOKEN_KEY" ]; then
    TEST_URL="https://$DOMAIN/if/flow/$RECOVERY_FLOW_SLUG/?flow_token=$TOKEN_KEY"
    
    echo "----------------------------------------------------------------"
    echo "✅ TOKEN CAPTURED: $TOKEN_KEY"
    echo "🌐 OPENING: $TEST_URL"
    echo "----------------------------------------------------------------"

    # 3. Launch and watch the skip logic work
    firefox --private-window "$TEST_URL" &
    sleep 2
    docker logs -f authentik-server --tail 50
else
    echo "❌ Capture failed. Full response was:"
    echo "$RESPONSE" | jq .
fi
exit



# >>>>>>>>>>>>>>>>>>>>>>>>>>  availability Verification >>>>>>>
U="https://auth.$DOMAIN/api/v3/stages/email/$EMAIL_STAGE_PK/"
echo $U
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U" | \
    jq '{name, host, from_address, use_global_settings}'
    U="https://auth.$DOMAIN/api/v3/stages/email/$EMAIL_STAGE_PK/"
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U" | \
    jq '{name, host, from_address, use_global_settings}'
    U="https://auth.$DOMAIN/api/v3/stages/email/$EMAIL_STAGE_PK/"
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U" | \
    jq '{name, host, from_address, use_global_settings}'

U="https://auth.$DOMAIN/api/v3/core/applications/vault-oidc/"
echo $U
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U" | jq '{name, slug, provider_obj}'

U="https://auth.$DOMAIN/api/v3/providers/oauth2/11/"
echo $U
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U" | jq '{client_id, redirect_uris}'

U="https://auth.$DOMAIN/application/o/vault-oidc/.well-known/openid-configuration"
curl -s -k "$U" | jq .issuer    

U="https://auth.$DOMAIN/api/v3/core/applications/vault-oidc/"
echo $U
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U" | jq '{name, slug, launch_url}'





# --- Gerar Token de Acesso via Vault OIDC ---
# Verifica se o método de auth está habilitado

echo "🔑 Gerando OIDC Token via Vault para o usuário $USER_NAME..."
# context vault
vault auth list | grep "oidc"
# Verifica a configuração de descoberta (Discovery)
vault read auth/oidc/config

# 1. Obter o token JWT do Vault (que o Authentik aceitará)
# Isso assume que o Vault é o OIDC Provider ou que ele pode gerar o token de identidade
vault login -method=oidc role="$AUTENTIK_OIDC_VAULT_STEWARD_ROLE" 

exit
#


VAULT_OIDC_TOKEN=$(vault read -field=token auth/oidc/oidc/callback)

# 2. Agora tentamos acessar o endpoint de system_tasks usando o contexto de sessão
# Se o Authentik estiver configurado para aceitar JWT do Vault:
echo "📊 Lendo System Tasks com contexto OIDC..."
USER_IDENTIFIER="$USER_NAME"
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
     -H "Accept: application/json" \
     -H "X-Authentik-Remote-User: $USER_NAME" \
     -H "X-Authentik-Remote-User: $USER_NAME" \
     -H "X-Authentik-Remote-Email: $USER_USER" \
    "https://auth.$DOMAIN/api/v3/admin/system_tasks/" | jq .


docker exec -it authentik-server timeout 2 bash -c "</dev/tcp/mailcrab.app-network/1025" && echo "✅ Port Open" || echo "❌ Connection Refused"
echo "🚀 Triggering Recovery Flow for user: $USER_IDENTIFIER"

# not allowed
U="https://auth.$DOMAIN/api/v3/flows/instances/$RECOVERY_FLOW_SLUG/execute/"
echo $U
curl -s -k -X POST "$U" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"uid\": \"$USER_IDENTIFIER\"}" | jq .

# any request to this endpont redirects to authentication
curl -s -k -X GET "$U" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" | jq .


# este resulta html, porque precisa de oidc token para responder.
U="https://auth.$DOMAIN/api/v3/admin/system_tasks/"
curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "$U"  | \
    grep -E "html|login|authe" 


#do we need a vault login oidc token to execute     "https://auth.$DOMAIN/api/v3/admin/system_tasks/" ?