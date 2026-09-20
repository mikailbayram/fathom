import { createConsumer, type Subscription } from "@rails/actioncable"

/**
 * One consumer per socket URL. Action Cable reconnects on its own, so the only
 * thing worth owning here is the subscription's lifetime.
 *
 * Keyed by URL rather than shared outright, because the two callers do not want
 * the same socket. A lead page subscribes to its scan with no token and shows a
 * demo preview that has one, and a single memoised consumer would hand whichever
 * mounted first to both -- making the preview's identity depend on render order
 * and on an operator cookie that an embedded widget never has.
 */
const consumers = new Map<string, ReturnType<typeof createConsumer>>()

/**
 * The visitor token travels on the socket URL as well, because an embedded
 * widget is a third-party iframe and the browser sends no cookie with it.
 */
function sharedConsumer(visitor?: string) {
  const url = visitor ? `/cable?v=${encodeURIComponent(visitor)}` : "/cable"
  const existing = consumers.get(url)
  if (existing) return existing

  const consumer = createConsumer(url)
  consumers.set(url, consumer)
  return consumer
}

export type ConversationEvent =
  | { type: "thinking" }
  | { type: "message"; message: unknown }

export function subscribeToConversation(
  slug: string,
  visitor: string | undefined,
  handlers: {
    onEvent: (event: ConversationEvent) => void
    onConnected?: () => void
    onDisconnected?: () => void
  },
): Subscription {
  return sharedConsumer(visitor).subscriptions.create(
    { channel: "ConversationChannel", slug },
    {
      received: (data: never) => handlers.onEvent(data as ConversationEvent),
      connected: () => handlers.onConnected?.(),
      disconnected: () => handlers.onDisconnected?.(),
    },
  )
}

/**
 * Scan progress. Passing a lead id subscribes to that lead's status payload;
 * passing none subscribes to the list, which is told only that something moved
 * and reloads its own props in response.
 */
export function subscribeToScan<T>(
  leadId: number | null,
  handlers: { onEvent: (event: T) => void; onConnected?: () => void; onDisconnected?: () => void },
): Subscription {
  return sharedConsumer().subscriptions.create(
    leadId === null ? { channel: "ScanChannel" } : { channel: "ScanChannel", lead_id: leadId },
    {
      received: (data: never) => handlers.onEvent(data as T),
      connected: () => handlers.onConnected?.(),
      disconnected: () => handlers.onDisconnected?.(),
    },
  )
}
