import { useCallback, useEffect, useRef, useState } from "react"
import { ArrowUp, ArrowUpRight, UserRound } from "lucide-react"
import { subscribeToConversation, type ConversationEvent } from "@/lib/cable"
import { FormattedMessage } from "@/components/FormattedMessage"
import { cn } from "@/lib/utils"
import type { ChatMessage as Message } from "@/types"

// If the answer has not arrived by now, something is wrong upstream and saying
// so beats an indicator that spins forever.
const ANSWER_TIMEOUT_MS = 45_000

/**
 * The conversation itself, shared by the public demo page and the preview
 * inside a lead. One implementation, so the preview is not a lookalike that can
 * drift from what a prospect actually sees.
 */
export function DemoChat({
  company,
  slug,
  visitor,
  askPath,
  handoffPath,
  suggestedQuestions,
  initialMessages,
  compact = false,
}: {
  company: string
  slug: string
  visitor?: string
  askPath: string
  handoffPath: string
  suggestedQuestions: string[]
  initialMessages: Message[]
  compact?: boolean
}) {
  const [messages, setMessages] = useState<Message[]>(initialMessages)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [draft, setDraft] = useState("")
  const endRef = useRef<HTMLDivElement>(null)
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const clearTimer = useCallback(() => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    timeoutRef.current = null
  }, [])

  useEffect(() => {
    const subscription = subscribeToConversation(slug, visitor, {
      onEvent: (event: ConversationEvent) => {
        if (event.type !== "message") return

        const message = event.message as Message
        setMessages((current) => (current.some((m) => m.id === message.id) ? current : [...current, message]))
        if (message.role === "assistant") {
          clearTimer()
          setPending(false)
        }
      },
    })

    return () => {
      subscription.unsubscribe()
      clearTimer()
    }
  }, [slug, visitor, clearTimer])

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth", block: "end" })
  }, [messages.length, pending])

  const ask = useCallback(
    async (asked: string) => {
      const question = asked.trim()
      if (!question || pending) return

      setDraft("")
      setPending(true)
      setError(null)

      clearTimer()
      timeoutRef.current = setTimeout(() => {
        setPending(false)
        setError("That's taking longer than it should. The answer may still arrive, or try asking again.")
      }, ANSWER_TIMEOUT_MS)

      try {
        const response = await fetch(askPath, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json",
            "X-CSRF-Token": document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "",
          },
          body: JSON.stringify({ question }),
        })

        if (response.status === 429) {
          clearTimer()
          setPending(false)
          setError("That's a lot of questions. Give it a minute and try again.")
          return
        }
        if (!response.ok) throw new Error(`HTTP ${response.status}`)

        const { message } = (await response.json()) as { message: Message }
        setMessages((current) => (current.some((m) => m.id === message.id) ? current : [...current, message]))
      } catch {
        clearTimer()
        setPending(false)
        setError("That didn't send. Check your connection and try again.")
      }
    },
    [askPath, pending, clearTimer],
  )

  // Offered when the agent could not answer, and whenever someone asks for a
  // person outright.
  const last = messages[messages.length - 1]
  const canEscalate =
    !pending && last?.role === "assistant" && (last.kind === "unavailable" || last.kind === "human_requested")

  // The question worth forwarding is the last real one, not "can I talk to a
  // human?" -- which tells their team nothing.
  const lastQuestion =
    [...messages]
      .reverse()
      .find((m, index) => m.role === "user" && !(index === 0 && last?.kind === "human_requested"))?.content ?? ""

  const escalate = useCallback(
    async (email: string) => {
      const response = await fetch(handoffPath, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "",
        },
        body: JSON.stringify({ question: lastQuestion, email, v: visitor }),
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const { message } = (await response.json()) as { message: Message }
      setMessages((current) => [...current, message])
    },
    [handoffPath, lastQuestion],
  )

  const started = messages.length > 0

  return (
    <div className="flex h-full flex-col">
      <div className={cn("flex-1", compact && "min-h-0 overflow-y-auto")}>
        {!started && suggestedQuestions.length > 0 && (
          <div className="space-y-2 pb-6">
            <div className="label-mono mb-2.5 uppercase text-muted-foreground">Try asking</div>
            {suggestedQuestions.map((question) => (
              <button
                key={question}
                type="button"
                onClick={() => ask(question)}
                className="w-full rounded-xl border border-border bg-surface px-3.5 py-2.5 text-left text-[0.8125rem] leading-snug tracking-tight text-foreground shadow-xs transition-colors outline-none hover:border-foreground/20 hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
              >
                {question}
              </button>
            ))}
          </div>
        )}

        {started && (
          <div className="space-y-4 pb-6">
            {messages.map((message) => (
              <Bubble key={message.id} message={message} />
            ))}
            {pending && <Typing />}
            {canEscalate && <AskAPerson company={company} question={lastQuestion} onSubmit={escalate} />}
            <div ref={endRef} />
          </div>
        )}
      </div>

      <div className={cn("bg-background pt-3", !compact && "sticky bottom-0 pb-6")}>
        {error && (
          <p role="alert" className="mb-2 text-[0.8125rem] text-destructive">
            {error}
          </p>
        )}

        <form
          onSubmit={(event) => {
            event.preventDefault()
            void ask(draft)
          }}
          className="relative"
        >
          <label htmlFor={`question-${slug}`} className="sr-only">
            Ask a question about {company}
          </label>
          <input
            id={`question-${slug}`}
            type="text"
            autoComplete="off"
            placeholder={`Ask about ${company}…`}
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            className="h-11 w-full rounded-full border border-input bg-surface py-3 pl-4 pr-12 text-[0.875rem] text-foreground shadow-xs outline-none transition-colors placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/25"
          />
          <button
            type="submit"
            disabled={pending || !draft.trim()}
            className="absolute right-1.5 top-1/2 flex size-8 -translate-y-1/2 items-center justify-center rounded-full bg-foreground text-background transition-opacity outline-none disabled:opacity-25 focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            <ArrowUp className="size-4" />
            <span className="sr-only">Send</span>
          </button>
        </form>
      </div>
    </div>
  )
}

/**
 * The visitor's turn sits right in a filled bubble; the answer sits left, on the
 * surface, with its sources attached. Sources stay visible rather than folded
 * away: they are the reason to believe the answer.
 */
function Bubble({ message }: { message: Message }) {
  if (message.role === "user") {
    return (
      <div className="flex justify-end animate-in fade-in slide-in-from-bottom-1 duration-200">
        <p className="max-w-[85%] rounded-2xl rounded-br-md bg-foreground px-3.5 py-2 text-[0.875rem] leading-relaxed text-background">
          {message.content}
        </p>
      </div>
    )
  }

  return (
    <div className="flex justify-start animate-in fade-in slide-in-from-bottom-1 duration-300">
      <div
        className={cn(
          // Every reply from the assistant reads the same. The dashed grey
          // variant made an honest "I don't have that" look like a degraded
          // answer rather than simply an answer.
          "max-w-[92%] rounded-2xl rounded-bl-md border border-border bg-surface px-3.5 py-2.5",
          // A human's reply is a different speaker, so it keeps its own mark.
          message.kind === "human" && "border-brand/30 bg-brand/5",
        )}
      >
        {message.kind === "human" && (
          <div className="mb-1.5 flex items-center gap-1.5">
            <UserRound className="size-3 text-brand" aria-hidden="true" />
            <span className="text-[0.6875rem] font-medium tracking-tight text-brand">Answered by the team</span>
          </div>
        )}
        <FormattedMessage content={message.content} />

        {message.sources.length > 0 && (
          <ul className="mt-3 space-y-2 border-t border-border pt-2.5">
            {message.sources.map((source, index) => (
              <li key={`${source.url}-${index}`}>
                <a
                  href={source.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group flex flex-col rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <span className="flex items-center gap-1 text-[0.75rem] font-medium text-foreground group-hover:underline underline-offset-4">
                    {source.title}
                    <ArrowUpRight className="size-3 text-muted-foreground" />
                  </span>
                  <span className="break-all font-mono text-[0.625rem] text-muted-foreground">{source.url}</span>
                </a>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

/**
 * The escape hatch. A question the documentation cannot answer is still a real
 * question from a real buyer, and ending on "I can't find that" wastes both the
 * prospect's interest and the signal about what the website fails to say.
 */
function AskAPerson({
  company,
  question,
  onSubmit,
}: {
  company: string
  question: string
  onSubmit: (email: string) => Promise<void>
}) {
  const [email, setEmail] = useState("")
  const [sending, setSending] = useState(false)
  const [failed, setFailed] = useState(false)

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    setSending(true)
    setFailed(false)
    try {
      await onSubmit(email)
    } catch {
      setSending(false)
      setFailed(true)
    }
  }

  return (
    <form onSubmit={submit} className="rounded-xl border border-dashed border-border bg-muted/40 p-3.5">
      <p className="text-[0.8125rem] leading-relaxed text-foreground">
        {question ? `Shall I send "${question}" to ${company}'s team?` : `Want me to put that to ${company}'s team?`}
      </p>
      <div className="mt-2.5 flex flex-col gap-2 sm:flex-row">
        <label htmlFor="handoff-email" className="sr-only">
          Your email, so they can reply
        </label>
        <input
          id="handoff-email"
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="you@company.com (optional)"
          className="h-9 flex-1 rounded-lg border border-input bg-surface px-3 text-[0.8125rem] text-foreground outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/25"
        />
        <button
          type="submit"
          disabled={sending}
          className="h-9 shrink-0 rounded-lg bg-foreground px-3.5 text-[0.8125rem] font-medium text-background transition-opacity outline-none disabled:opacity-50 focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        >
          {sending ? "Sending…" : "Ask their team"}
        </button>
      </div>
      {failed && (
        <p role="alert" className="mt-2 text-[0.75rem] text-destructive">
          That didn&rsquo;t send. Try again in a moment.
        </p>
      )}
    </form>
  )
}

/** Dots only. The running commentary was noise. */
function Typing() {
  return (
    <div className="flex justify-start" role="status" aria-live="polite">
      <span className="sr-only">Thinking</span>
      <div className="flex items-center gap-1 rounded-2xl rounded-bl-md border border-border bg-surface px-3.5 py-3">
        <span className="size-1.5 animate-bounce rounded-full bg-muted-foreground/50 [animation-delay:-0.3s]" />
        <span className="size-1.5 animate-bounce rounded-full bg-muted-foreground/50 [animation-delay:-0.15s]" />
        <span className="size-1.5 animate-bounce rounded-full bg-muted-foreground/50" />
      </div>
    </div>
  )
}
