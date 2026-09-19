# Webhook delivery and retries

Acme delivers an event to your endpoint whenever a sync run finishes, fails, or is cancelled.

## Delivery

Acme sends a POST request with a JSON body and an HMAC signature header. Your endpoint should respond with a 2xx status within 10 seconds.

## Retry behaviour

When a webhook endpoint fails to accept a delivery, Acme retries the delivery six times using exponential backoff over a 24 hour window. The intervals are 1 minute, 5 minutes, 30 minutes, 2 hours, 6 hours and 12 hours.

After the sixth failed attempt the event is moved to a dead-letter queue and no further automatic attempts are made. Events remain in the dead-letter queue for 30 days.

## Replaying failed deliveries

Dead-lettered events can be replayed from the workspace settings, or through the replay endpoint in the API. Replays are counted against your API rate limit.

## Endpoint failures that are not retried

A 410 Gone response disables the endpoint immediately and no retries are attempted, because a 410 states that the endpoint is permanently unavailable.
