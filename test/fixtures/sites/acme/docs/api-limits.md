# API rate limits

The Acme API enforces per-workspace rate limits.

## Limits by plan

Starter workspaces are limited to 60 requests per minute. Business workspaces are limited to 600 requests per minute. Enterprise workspaces are limited to 3,000 requests per minute, and the limit can be raised on request.

## Handling a 429 response

When you exceed the limit the API returns a 429 status with a Retry-After header giving the number of seconds to wait. Clients should honour Retry-After rather than retrying immediately.

## Idempotency

Write requests accept an Idempotency-Key header. Acme stores the result of a keyed request for 24 hours, so a retry with the same key returns the original result instead of creating a duplicate record.
