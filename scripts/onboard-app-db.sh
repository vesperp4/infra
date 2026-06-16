#!/usr/bin/env bash
# Idempotently maps the app's managed identity to a least-privilege PostgreSQL
# role (passwordless Entra auth) and grants it on the app database.
#
# Runs in the deploy workflow AFTER the server exists. Authenticates to Postgres
# as the CI deploy identity (a server Entra admin) using a short-lived Entra
# token — no password. Temporarily opens the server firewall to this runner's IP
# (GitHub runners are not "Azure services", so the AllowAzureServices rule does
# not cover them) and removes the rule on exit.
#
# Requires: az (already logged in as the deploy identity), psql.
#
# Usage: onboard-app-db.sh <rg> <server> <db> <app-identity-name> <shared-rg>
set -euo pipefail

rg="${1:?resource group required}"
server="${2:?server name required}"
db="${3:?database name required}"
appRole="${4:?app identity name required}"
sharedRg="${5:?shared resource group required}"

fqdn="${server}.postgres.database.azure.com"

# The deploy identity's own name is its Postgres admin login.
adminUser="$(az account show --query user.name -o tsv)"
# Object ID the Entra token will carry for the app identity.
appOid="$(az identity show -g "$sharedRg" -n "$appRole" --query principalId -o tsv)"

# Temporarily allow this runner's public IP, and always clean it up.
runnerIp="$(curl -fsS https://api.ipify.org)"
ruleName="ci-onboard-$(date +%s)"
cleanup() {
  az postgres flexible-server firewall-rule delete \
    -g "$rg" --server-name "$server" --name "$ruleName" --yes >/dev/null 2>&1 || true
}
trap cleanup EXIT
az postgres flexible-server firewall-rule create \
  -g "$rg" --server-name "$server" --name "$ruleName" \
  --start-ip-address "$runnerIp" --end-ip-address "$runnerIp" >/dev/null

# Entra access token for PostgreSQL, used as the connection password.
token="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"

# 1) Create the Entra-mapped role (cluster-level), tied to the identity's OID.
PGPASSWORD="$token" psql \
  "host=$fqdn port=5432 dbname=postgres user=$adminUser sslmode=require" \
  -v ON_ERROR_STOP=1 <<SQL
DO \$\$ BEGIN
  PERFORM pgaadauth_create_principal_with_oid('$appRole', '$appOid', 'service', false, false);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'role $appRole may already exist: %', SQLERRM;
END \$\$;
SQL

# 2) Grant least-privilege on the app database (idempotent).
PGPASSWORD="$token" psql \
  "host=$fqdn port=5432 dbname=$db user=$adminUser sslmode=require" \
  -v ON_ERROR_STOP=1 <<SQL
GRANT CONNECT ON DATABASE "$db" TO "$appRole";
GRANT USAGE, CREATE ON SCHEMA public TO "$appRole";
GRANT ALL ON ALL TABLES IN SCHEMA public TO "$appRole";
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO "$appRole";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$appRole";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$appRole";
SQL

echo "onboarded $appRole on $db@$server"
