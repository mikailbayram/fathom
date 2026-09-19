import { cn } from "@/lib/utils"
import { EvidenceExcerpt } from "@/components/EvidenceExcerpt"
import { SourceLink } from "@/components/SourceLink"
import { Findability, bandFor } from "@/components/Findability"
import type { Source } from "@/types"

/**
 * The signature moment of the product.
 *
 * The gap is communicated by weight, not by colour: the buyer-visible side is
 * muted with a dashed rule, the deep side is full-contrast with a solid one and
 * the answer quoted beneath it. You can read the difference with the labels
 * covered, and it survives being printed in black and white.
 */
export function CorpusComparison({
  buyerVisible,
  deep,
  gap,
  domain,
}: {
  buyerVisible: { answerable: boolean; confidence: number; answer: string | null }
  deep: { answerable: boolean; confidence: number; answer: string | null; source: Source | null }
  gap: number
  domain: string
}) {
  return (
    <div>
      <div className="grid gap-px overflow-hidden rounded-lg border border-border bg-border md:grid-cols-2">
        <Column
          label="Buyer-visible website"
          state={buyerVisible.answerable ? "found" : "absent"}
          confidence={buyerVisible.confidence}
        >
          {buyerVisible.answerable && buyerVisible.answer ? (
            <p className="text-[0.8125rem] leading-relaxed text-foreground/75">{buyerVisible.answer}</p>
          ) : (
            <p className="text-[0.8125rem] leading-relaxed text-muted-foreground">
              Nothing on the pages a buyer meets on the primary marketing journey establishes an answer.
            </p>
          )}
        </Column>

        <Column label="Deep public content" state={deep.answerable ? "found" : "absent"} confidence={deep.confidence}>
          {deep.answerable && deep.answer ? (
            <>
              <EvidenceExcerpt className="border-l-foreground/25">{deep.answer}</EvidenceExcerpt>
              {deep.source && (
                <div className="mt-4">
                  <div className="label-mono mb-1.5 uppercase text-muted-foreground">Source</div>
                  <SourceLink source={deep.source} />
                </div>
              )}
            </>
          ) : (
            <p className="text-[0.8125rem] leading-relaxed text-muted-foreground">
              No public documentation establishes an answer either.
            </p>
          )}
        </Column>
      </div>

      <GapBar gap={gap} source={deep.source} domain={domain} />
    </div>
  )
}

function Column({
  label,
  state,
  confidence,
  children,
}: {
  label: string
  state: "found" | "absent"
  confidence: number
  children: React.ReactNode
}) {
  const absent = state === "absent"

  return (
    <section className={cn("bg-background p-5 md:p-6", absent && "bg-muted/40")}>
      <div className="label-mono uppercase text-muted-foreground">{label}</div>

      <div className="mt-4 flex items-baseline gap-3">
        {/* The verdict is words first; the rule underneath repeats it as weight. */}
        <span
          className={cn(
            "text-[0.9375rem] font-medium tracking-tight",
            absent ? "text-muted-foreground" : "text-foreground",
          )}
        >
          {absent ? "No definitive answer" : "Definitive answer found"}
        </span>
        <span className="ml-auto font-mono text-[0.8125rem] tabular text-muted-foreground">{confidence}%</span>
      </div>

      <div
        aria-hidden="true"
        className={cn("mt-3 h-px w-full", absent ? "border-t border-dashed border-border" : "bg-border")}
      >
        <div
          className={cn("h-px", absent ? "bg-muted-foreground/30" : "bg-foreground/70")}
          style={{ width: `${Math.max(confidence, 2)}%` }}
        />
      </div>

      <div className="mt-5">{children}</div>
    </section>
  )
}

/**
 * "Discoverability gap" is a term of art nobody outside this codebase uses. The
 * heading says what the number means, and the sentence underneath says it again
 * in the concrete: where the fact lives, and whether a buyer would get there.
 */
function GapBar({ gap, source, domain }: { gap: number; source: Source | null; domain: string }) {
  return (
    <div className="pt-5">
      <div className="flex items-baseline justify-between gap-4">
        <h3 className="text-[0.8125rem] font-medium tracking-tight text-foreground">
          How hard this is for a buyer to find
        </h3>
        <Findability score={gap} domain={domain} />
      </div>

      {/* The measure runs the full width of the comparison it describes. */}
      <div className="mt-2 h-1 w-full rounded-full bg-border" aria-hidden="true">
        <div className={cn("h-1 rounded-full", bandFor(gap).dot)} style={{ width: `${gap}%` }} />
      </div>

      <p className="mt-2.5 text-[0.8125rem] leading-relaxed text-muted-foreground">
        <span className="font-mono text-[0.75rem] text-foreground">{gap} out of 100</span>
        {" — "}
        {source ? (
          <>
            published in {source.page_type_label.toLowerCase()} on{" "}
            <span className="font-mono text-[0.75rem]">{source.host ?? domain}</span>.{" "}
            {bandFor(gap).explain(domain)}
          </>
        ) : (
          bandFor(gap).explain(domain)
        )}
      </p>
    </div>
  )
}
