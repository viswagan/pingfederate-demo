#!/bin/sh
# ─────────────────────────────────────────────────────────────────────
# PingFederate one-shot configuration via Admin API
#
# Provisions everything the three demo flows need, end to end:
#
#   Flow 1 — OIDC browser login (authorization_code)
#     scopes → ATM → PCV (user store) → HTML Form adapter →
#     IdP Adapter Mapping → Default access-token mapping →
#     OIDC Policy → demo-oidc-client (with OIDC policy + ATM assigned)
#
#   Flow 2 — opaque token introspection   (demo-rs-client)
#   Flow 3 — M2M client credentials       (demo-m2m-client)
#
# Authentication mode: IdP Adapter Mapping (the global "IdP Authentication
# Policies" toggle is OFF). PF only offers an authentication method for the
# authorization-code flow when BOTH an IdP Adapter Mapping AND a Default
# access-token mapping exist — without them PF returns
# "There are no authentication methods available for OAuth".
#
# Runs once on first `docker compose --profile autoconfig up`; PF persists
# config in the pf-data volume, so re-runs hit "already exists" and skip.
# A `docker compose down -v` wipes the volume — this script rebuilds it all.
#
# NOTE: PingFederate Admin API requires HTTPS. We use --insecure throughout
# because PF ships with a self-signed cert by default.
# ─────────────────────────────────────────────────────────────────────

set -e

PF_ADMIN="${PF_ADMIN_URL:-https://pingfederate:9999}"
# PingFederate 13.x Docker image always creates the admin account with
# username "administrator" (ROOT_USER) regardless of PF_ADMIN_USER_USERNAME.
BASE_AUTH="administrator:${PF_ADMIN_PASSWORD:-Admin1234!}"
APP_REDIRECT="http://app:8080/login/oauth2/code/pingfed-oidc"
LOCALHOST_REDIRECT="http://localhost:8080/login/oauth2/code/pingfed-oidc"

# Demo user (browser login — Flow 1)
DEMO_USER="${DEMO_USER:-user1}"
DEMO_PASSWORD="${DEMO_PASSWORD:-Password1!}"

echo "==> Waiting for PingFederate Admin API..."
until curl -sk --insecure \
    -u "$BASE_AUTH" \
    -H "X-XSRF-Header: PingFederate" \
    -o /dev/null -w "%{http_code}" \
    "$PF_ADMIN/pf-admin-api/v1/serverSettings" 2>/dev/null \
    | grep -q "^200$"; do
  echo "    Not ready yet, retrying in 5s..."
  sleep 5
done
echo "==> PingFederate Admin API is up"

# ── Helper function ───────────────────────────────────────────────────
pf_api() {
  METHOD=$1
  ENDPOINT=$2
  shift 2
  curl -sf --insecure \
    -u "$BASE_AUTH" \
    -H "Content-Type: application/json" \
    -H "X-XSRF-Header: PingFederate" \
    -X "$METHOD" \
    "$PF_ADMIN/pf-admin-api/v1$ENDPOINT" \
    "$@"
}

# ── 1. Enable the OAuth Authentication API ───────────────────────────
echo "==> Enabling OAuth2 server settings..."
pf_api PUT /authenticationApi/settings -d '{
  "apiEnabled": true
}' || true

# Adapter-mapping mode: keep IdP Authentication Policies OFF so PF uses the
# IdP Adapter Mapping (created below) as the authentication source. With this
# ON, PF would ignore the adapter mapping and require an Authentication Policy
# + APC mapping instead — do not mix the two.
echo "==> Ensuring IdP Authentication Policies are disabled (adapter-mapping mode)..."
pf_api PUT /authenticationPolicies/settings -d '{
  "enableIdpAuthnSelection": false,
  "enableSpAuthnSelection": false
}' || true

# ── 2. Register OAuth scopes ─────────────────────────────────────────
# openid is built-in; profile/email/api.read must be registered or the
# authorization request fails with invalid_scope.
echo "==> Registering common OAuth scopes..."
for scope_def in \
  'openid|OpenID Connect' \
  'profile|User profile' \
  'email|Email address' \
  'api.read|Read access to API'; do
  s_name="${scope_def%%|*}"
  s_desc="${scope_def#*|}"
  pf_api POST /oauth/authServerSettings/scopes/commonScopes -d "{
    \"name\": \"$s_name\",
    \"description\": \"$s_desc\",
    \"dynamic\": false
  }" >/dev/null || echo "    scope $s_name may already exist, continuing..."
done

# ── 3. Create the Access Token Manager (opaque reference tokens) ─────
# Instance ID must be alphanumeric only — "demoATM" works, "demo-atm" does not.
echo "==> Creating Access Token Manager (demoATM)..."
pf_api POST /oauth/accessTokenManagers -d '{
  "id": "demoATM",
  "name": "Demo ATM",
  "pluginDescriptorRef": {
    "id": "org.sourceid.oauth20.token.plugin.impl.ReferenceBearerAccessTokenManagementPlugin"
  },
  "configuration": {
    "tables": [],
    "fields": [
      { "name": "Token Length", "value": "28" },
      { "name": "Token Lifetime", "value": "120" },
      { "name": "Lifetime Extension Policy", "value": "NONE" },
      { "name": "Maximum Token Lifetime", "value": "" },
      { "name": "Lifetime Extension Threshold Percentage", "value": "30" },
      { "name": "Mode for Synchronous RPC", "value": "3" },
      { "name": "RPC Timeout", "value": "500" },
      { "name": "Expand Scope Groups", "value": "false" }
    ]
  },
  "attributeContract": {
    "coreAttributes": [],
    "extendedAttributes": [
      { "name": "sub", "multiValued": false }
    ]
  }
}' || echo "    ATM may already exist, continuing..."

# ── 4. Create the Password Credential Validator (user store) ─────────
echo "==> Creating Password Credential Validator (simplepcv) with user $DEMO_USER..."
pf_api POST /passwordCredentialValidators -d "{
  \"id\": \"simplepcv\",
  \"name\": \"SimplePCV\",
  \"pluginDescriptorRef\": {
    \"id\": \"org.sourceid.saml20.domain.SimpleUsernamePasswordCredentialValidator\"
  },
  \"configuration\": {
    \"tables\": [
      {
        \"name\": \"Users\",
        \"rows\": [
          {
            \"fields\": [
              { \"name\": \"Username\", \"value\": \"$DEMO_USER\" },
              { \"name\": \"Password\", \"value\": \"$DEMO_PASSWORD\" },
              { \"name\": \"Confirm Password\", \"value\": \"$DEMO_PASSWORD\" },
              { \"name\": \"Relax Password Requirements\", \"value\": \"false\" }
            ]
          }
        ]
      }
    ],
    \"fields\": []
  }
}" || echo "    PCV may already exist, continuing..."

# ── 5. Create the HTML Form IdP Adapter (the login page) ────────────
# Wires the PCV in via the Credential Validators table. Unspecified plugin
# fields take their descriptor defaults.
echo "==> Creating HTML Form IdP Adapter (demoHTMLForm)..."
pf_api POST /idp/adapters -d '{
  "id": "demoHTMLForm",
  "name": "Demo HTML Form",
  "pluginDescriptorRef": {
    "id": "com.pingidentity.adapters.htmlform.idp.HtmlFormIdpAuthnAdapter"
  },
  "configuration": {
    "tables": [
      {
        "name": "Credential Validators",
        "rows": [
          { "fields": [ { "name": "Password Credential Validator Instance", "value": "simplepcv" } ] }
        ]
      }
    ],
    "fields": [
      { "name": "Challenge Retries", "value": "3" }
    ]
  },
  "attributeContract": {
    "coreAttributes": [
      { "name": "policy.action" },
      { "name": "username", "pseudonym": true }
    ],
    "extendedAttributes": []
  },
  "attributeMapping": {
    "attributeContractFulfillment": {
      "policy.action": { "source": { "type": "ADAPTER" }, "value": "policy.action" },
      "username":      { "source": { "type": "ADAPTER" }, "value": "username" }
    }
  }
}' || echo "    Adapter may already exist, continuing..."

# ── 6. Map the adapter as an OAuth authentication source ─────────────
# Without this PF has no authentication source for the authorization-code
# flow ("Please map an IdP Adapter or IdP connection first").
echo "==> Creating IdP Adapter Mapping (demoHTMLForm -> persistent grant)..."
pf_api POST /oauth/idpAdapterMappings -d '{
  "id": "demoHTMLForm",
  "idpAdapterRef": { "id": "demoHTMLForm" },
  "attributeContractFulfillment": {
    "USER_KEY":  { "source": { "type": "ADAPTER" }, "value": "username" },
    "USER_NAME": { "source": { "type": "ADAPTER" }, "value": "username" }
  }
}' || echo "    IdP adapter mapping may already exist, continuing..."

# ── 7. Access token mappings (how the ATM "sub" gets fulfilled) ──────
# Default context = authorization-code / browser logins. Source is the
# persistent grant USER_KEY. NOTE the enum is OAUTH_PERSISTENT_GRANT, not
# PERSISTENT_GRANT. This mapping is the second half of what PF needs before
# it will offer an authentication method for Flow 1.
echo "==> Creating Default access-token mapping (Flow 1)..."
pf_api POST /oauth/accessTokenMappings -d '{
  "id": "default|demoATM",
  "context": { "type": "DEFAULT" },
  "accessTokenManagerRef": { "id": "demoATM" },
  "attributeContractFulfillment": {
    "sub": { "source": { "type": "OAUTH_PERSISTENT_GRANT" }, "value": "USER_KEY" }
  }
}' || echo "    Default token mapping may already exist, continuing..."

# Client-credentials context = Flows 2 & 3 (no user). sub is the client id —
# source CONTEXT / ClientId. NOTE: do NOT use CONTEXT / OAuthAuthorizationDetails
# here; it resolves to nothing for client_credentials and the token request fails
# with invalid_grant "No attributes found in the context of this grant".
echo "==> Creating client_credentials access-token mapping (Flows 2 & 3)..."
pf_api POST /oauth/accessTokenMappings -d '{
  "id": "client_credentials|demoATM",
  "context": { "type": "CLIENT_CREDENTIALS" },
  "accessTokenManagerRef": { "id": "demoATM" },
  "attributeContractFulfillment": {
    "sub": { "source": { "type": "CONTEXT" }, "value": "ClientId" }
  }
}' || echo "    client_credentials token mapping may already exist, continuing..."

# ── 8. OpenID Connect Policy (ID token shape for Flow 1) ─────────────
# sub is fulfilled from the access token (source TOKEN), NOT from an
# Authentication Policy Contract (the API rejects APC here).
echo "==> Creating OpenID Connect Policy (demoOIDCPolicy)..."
pf_api POST /oauth/openIdConnect/policies -d '{
  "id": "demoOIDCPolicy",
  "name": "Demo OIDC Policy",
  "accessTokenManagerRef": { "id": "demoATM" },
  "attributeContract": {
    "coreAttributes": [ { "name": "sub", "multiValued": false } ],
    "extendedAttributes": []
  },
  "attributeMapping": {
    "attributeContractFulfillment": {
      "sub": { "source": { "type": "TOKEN" }, "value": "sub" }
    }
  }
}' || echo "    OIDC policy may already exist, continuing..."

# ── 9. Create OIDC client (Flow 1 — authorization code) ─────────────
# Assigns the ATM and the OIDC policy created above.
echo "==> Creating OIDC client (Flow 1)..."
pf_api POST /oauth/clients -d "{
  \"clientId\": \"${OIDC_CLIENT_ID:-demo-oidc-client}\",
  \"name\": \"Demo OIDC Client\",
  \"grantTypes\": [\"AUTHORIZATION_CODE\"],
  \"clientAuth\": {\"type\": \"SECRET\", \"secret\": \"${OIDC_CLIENT_SECRET:-OidcSecret123!}\"},
  \"redirectUris\": [\"$APP_REDIRECT\", \"$LOCALHOST_REDIRECT\"],
  \"allowAuthenticationApiInit\": false,
  \"requireSignedRequests\": false,
  \"restrictScopes\": false,
  \"defaultAccessTokenManagerRef\": {\"id\": \"demoATM\"},
  \"oidcPolicy\": {
    \"policyGroup\": {\"id\": \"demoOIDCPolicy\"},
    \"grantAccessSessionRevocationApi\": false,
    \"pingAccessLogoutCapable\": false,
    \"pairwiseIdentifierUserType\": false,
    \"idTokenSigningAlgorithm\": \"RS256\"
  },
  \"refreshRolling\": \"SERVER_DEFAULT\",
  \"persistentGrantExpirationType\": \"SERVER_DEFAULT\"
}" || echo "    OIDC client may already exist, continuing..."

# ── 10. Create Resource Server client (Flow 2 — introspection creds) ─
# ACCESS_TOKEN_VALIDATION (the "Resource Server" / validate_bearer grant) is
# required to call /as/introspect.oauth2 — without it PF returns
# unauthorized_client even with correct credentials.
echo "==> Creating Resource Server client (Flow 2)..."
pf_api POST /oauth/clients -d "{
  \"clientId\": \"${RS_CLIENT_ID:-demo-rs-client}\",
  \"name\": \"Demo Resource Server\",
  \"grantTypes\": [\"CLIENT_CREDENTIALS\", \"ACCESS_TOKEN_VALIDATION\"],
  \"clientAuth\": {\"type\": \"SECRET\", \"secret\": \"${RS_CLIENT_SECRET:-RsSecret123!}\"},
  \"restrictScopes\": false,
  \"defaultAccessTokenManagerRef\": {\"id\": \"demoATM\"},
  \"allowAuthenticationApiInit\": false,
  \"requireSignedRequests\": false
}" || echo "    RS client may already exist, continuing..."

# ── 11. Create M2M client (Flow 3 — client credentials) ─────────────
echo "==> Creating M2M client (Flow 3)..."
pf_api POST /oauth/clients -d "{
  \"clientId\": \"${M2M_CLIENT_ID:-demo-m2m-client}\",
  \"name\": \"Demo M2M Client\",
  \"grantTypes\": [\"CLIENT_CREDENTIALS\"],
  \"clientAuth\": {\"type\": \"SECRET\", \"secret\": \"${M2M_CLIENT_SECRET:-M2mSecret123!}\"},
  \"restrictScopes\": true,
  \"restrictedScopes\": [\"api.read\"],
  \"defaultAccessTokenManagerRef\": {\"id\": \"demoATM\"},
  \"allowAuthenticationApiInit\": false,
  \"requireSignedRequests\": false
}" || echo "    M2M client may already exist, continuing..."

echo ""
echo "==> PingFederate configuration complete!"
echo "    Admin console: https://localhost:9999/pingfederate/app"
echo "    Runtime:       https://localhost:9031"
echo "    Clients:       ${OIDC_CLIENT_ID:-demo-oidc-client} | ${RS_CLIENT_ID:-demo-rs-client} | ${M2M_CLIENT_ID:-demo-m2m-client}"
echo "    Flow 1 login:  $DEMO_USER / $DEMO_PASSWORD"
