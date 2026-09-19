import { cn } from "@/lib/utils"

/**
 * How hard a published fact is for a buyer to reach, as a label rather than a
 * bare number.
 *
 * Colour carries the same thing the word does, never anything extra: red means
 * buried, green means a buyer can already read it. Someone who cannot
 * distinguish the two reads exactly the same verdict from the text, and the
 * score stays visible for anyone who wants the number.
 */
type Band = { label: string; tone: string; dot: string; explain: (domain: string) => string }

export const MISSING_BAND: Band = {
  label: "Not published",
  tone: "border-foreground/25 bg-foreground/5 text-foreground",
  dot: "bg-foreground/60",
  explain: (domain) => `Nothing on ${domain} answers this at all.`,
}

export function bandFor(score: number): Band {
  if (score >= 70) {
    return {
      label: "Buried",
      tone: "border-negative/30 bg-negative-surface text-negative",
      dot: "bg-negative",
      explain: (domain) => `Someone browsing ${domain} would not reach this.`,
    }
  }
  if (score >= 40) {
    return {
      label: "Hard to find",
      tone: "border-warning/30 bg-warning-surface text-warning",
      dot: "bg-warning",
      explain: (domain) => `Someone browsing ${domain} would have to go looking for this.`,
    }
  }
  return {
    label: "Already public",
    tone: "border-positive/30 bg-positive-surface text-positive",
    dot: "bg-positive",
    explain: (domain) => `${domain} already says much the same thing.`,
  }
}

/**
 * The word alone. An unexplained number beside it just competes with the
 * friction score for attention -- the detail view is where the figure belongs,
 * next to the sentence that says what it measures.
 */
export function Findability({
  score,
  domain,
  kind = "buried",
  className,
}: {
  score: number
  domain?: string
  kind?: "buried" | "missing"
  className?: string
}) {
  const band = kind === "missing" ? MISSING_BAND : bandFor(score)
  const explanation = `${band.label}: ${band.explain(domain ?? "the main site")}`

  return (
    <span
      title={explanation}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-[0.75rem] font-medium tracking-tight",
        band.tone,
        className,
      )}
    >
      <span className={cn("size-1.5 shrink-0 rounded-full", band.dot)} aria-hidden="true" />
      {band.label}
      <span className="sr-only">. {band.explain(domain ?? "the main site")}</span>
    </span>
  )
}
