using '../../../bicep/web.bicep'

param environment = 'dev'

param appName = 'portal-web'

// `portal.dev.vesperp4.com` is bound OUT-OF-BAND (2026-07-02), not via this
// param — same pattern and same reason as the prod portal/mainsite domains:
// declaring `customDomains` makes ARM poll the SWA's async operation-status
// resource at subscription/location scope, which the RG-scoped deploy identity
// cannot read, so the deployment hangs even though the bind succeeds. The
// domain is bound and Ready (grey-cloud CNAME `portal.dev` → this SWA's
// defaultHostname, cname-delegation validated); incremental deploys don't
// prune it. To codify it in bicep instead, grant the deploy identities Reader
// at subscription scope, then re-add `customDomains` here.
// The dev API (PUBLIC_BASE_URL, magic-link/confirm emails) already points at
// this FQDN, and the vp4_session cookie is same-site with it.
