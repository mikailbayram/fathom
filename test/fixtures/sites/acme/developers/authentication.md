# API authentication

The Acme API supports two authentication methods.

## API keys

Workspace administrators can issue API keys scoped to a set of permissions. Keys are shown once at creation and can be revoked at any time.

## OAuth 2.0

For applications acting on behalf of a user, Acme supports the OAuth 2.0 authorization code flow with PKCE. Access tokens expire after one hour; refresh tokens are valid for 30 days.

Machine-to-machine access uses the client credentials grant and is available on the Enterprise plan.
