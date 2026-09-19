# Custom roles and permissions

Acme ships with three predefined roles: Owner, Editor and Viewer. Predefined roles cover most teams, but larger organisations usually need something narrower.

## Defining a custom role

Administrators can define custom RBAC roles with granular resource permissions rather than using only the predefined roles. Custom roles are available on the Enterprise plan.

A custom role is a named set of permissions. Each permission grants one action on one resource type, so you can allow a role to read connection settings without allowing it to run a sync or view synced records.

## Scoping a role to resources

Custom roles can be scoped to individual connections or to a folder of connections, rather than to the whole workspace. This is how teams share one Acme workspace without sharing data across business units.

## Assigning roles

Administrators assign roles to users directly or through a group. When SCIM provisioning is enabled, group membership from your identity provider drives role assignment automatically.

## Limits

A workspace may define up to 50 custom roles. Custom roles cannot grant permissions that the assigning administrator does not hold.
