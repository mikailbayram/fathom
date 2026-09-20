import { DemoChat } from "@/components/DemoChat"
import type { ChatMessage as Message } from "@/types"

/**
 * The public, shareable demo. Deliberately simpler than the internal product:
 * no navigation, no scores, nothing to explain before it is useful.
 */
export default function Show({
  company,
  domain,
  slug,
  ask_path,
  handoff_path,
  suggested_questions,
  messages,
  visitor,
  embedded = false,
}: {
  company: string
  domain: string
  slug: string
  ask_path: string
  handoff_path: string
  suggested_questions: string[]
  messages: Message[]
  visitor: string
  embedded?: boolean
}) {
  // Embedded, the page is a panel on someone else's site: it fills its frame
  // and drops the standalone page's generous margins.
  return (
    <>
      {/* Sized to the frame, not to the viewport.
       *
       * The shared layout puts min-h-dvh on the body, and a viewport unit
       * inside an iframe is not reliably the frame's own height. When it
       * resolves larger, the body stretches past the frame, the frame grows a
       * scrollbar of its own beside the message list's, and the space below
       * the footer goes blank. Anchoring to 100% of the frame removes the
       * question, and the document is not allowed to scroll at all -- the
       * message list is the only thing here that should.
       *
       * #app is in the chain because a percentage height resolves against the
       * parent's, and Inertia's mount div has none: h-full on the page root
       * fell back to content height and overflowed a short frame instead of
       * fitting it. */}
      {embedded && (
        <style>{"html,body,#app{height:100%;min-height:0;overflow:hidden}"}</style>
      )}
    <div
      className={
        embedded
          ? "flex h-full flex-col overflow-hidden px-4 pt-4"
          : "mx-auto flex min-h-dvh max-w-2xl flex-col px-5 sm:px-6"
      }
    >
      <header className={embedded ? "pb-4" : "pb-7 pt-12 sm:pt-16"}>
        <div className="label-mono uppercase text-muted-foreground">{domain}</div>
        <h1
          className={
            embedded
              ? "mt-1 text-[1.0625rem] font-semibold tracking-tight text-foreground"
              : "mt-2.5 text-[1.625rem] font-semibold leading-tight tracking-tighter text-foreground sm:text-[2rem]"
          }
        >
          Ask anything about {company}
        </h1>
        {!embedded && (
          <p className="mt-2.5 max-w-[56ch] text-[0.8125rem] leading-relaxed text-muted-foreground">
            Answers come only from {company}&rsquo;s public website and documentation, with a link to the page each
            one came from.
          </p>
        )}
      </header>

      <DemoChat
        company={company}
        slug={slug}
        visitor={visitor}
        askPath={ask_path}
        handoffPath={handoff_path}
        suggestedQuestions={suggested_questions}
        initialMessages={messages}
        compact={embedded}
      />

      <p className="pb-4 text-center text-[0.625rem] text-muted-foreground">
        An independent analysis of {company}&rsquo;s public content. Not affiliated with {company}.
      </p>
    </div>
    </>
  )
}
