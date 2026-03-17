RECOVERY_FLOW_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/flows/instances/?slug=$RECOVERY_FLOW_SLUG" | \
        jq -r '.results[0].pk')


# 1. Find your Brand (usually by domain)
BRAND_PK=$(curl -sk -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    "https://auth.$DOMAIN/api/v3/core/brands/?domain=$DOMAIN" | jq -r '.results[0].brand_uuid')

# 2. Update Brand to use your Recovery Flow
echo "🔗 Linking Flow $RECOVERY_FLOW_PK to Brand $BRAND_PK..."
curl -s -k -X PATCH "https://auth.$DOMAIN/api/v3/core/brands/$BRAND_PK/" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"flow_recovery\": \"$RECOVERY_FLOW_PK\",
        \"branding_title\": \"Home2500 Recovery\",
        \"default\": true
    }" | jq -r '"Brand updated: " + .domain + " (Recovery Flow: " + .flow_recovery + ")"'