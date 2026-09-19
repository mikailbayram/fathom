# Migrating to Acme

Most enterprise migrations to Acme take four to six weeks from kickoff to production cutover.

## Timeline

Week one is discovery: inventorying the pipelines you run today and the systems they touch. Weeks two and three are connection configuration and schema mapping. Week four is parallel running, where Acme and your existing pipelines run side by side so results can be compared. Cutover follows once the comparison is clean.

Organisations migrating more than 200 pipelines should plan for six to eight weeks.

## Prerequisites

Before a migration begins you will need administrator credentials for every source and destination system, a list of the pipelines in scope with their owners, and a nominated technical contact who can approve schema mappings.

Network allowlisting, if your systems require it, must be completed before week two.

## Historical data

Historical records can be backfilled during migration. Backfills of more than 500 million rows are scheduled with your support contact so they do not contend with production syncs.
