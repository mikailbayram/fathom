// @rails/actioncable ships no types and has no @types package.
declare module "@rails/actioncable" {
  export interface Subscription {
    unsubscribe(): void
    perform(action: string, data?: object): void
  }

  export interface Consumer {
    subscriptions: {
      create(
        channel: string | { channel: string; [key: string]: unknown },
        handlers?: {
          received?: (data: never) => void
          connected?: () => void
          disconnected?: () => void
          rejected?: () => void
        },
      ): Subscription
    }
    disconnect(): void
  }

  export function createConsumer(url?: string): Consumer
}
