import { ArrowUpRight } from "lucide-react"
import { cn } from "@/lib/utils"
import type { Source } from "@/types"

/**
 * A link back to the original public page. Always the real URL, in mono, so a
 * reader can check the claim rather than take our word for it.
 */
export function SourceLink({ source, className }: { source: Source; className?: string }) {
  return (
    <a
      href={source.url}
      target="_blank"
      rel="noopener noreferrer"
      className={cn(
        // min-w-0 is what keeps a long URL from setting the min-content width
        // of the grid or flex track it sits in. Without it the URL cannot
        // shrink, so the column grows to fit it and the phone gets a sideways
        // scrollbar -- or, inside an overflow-hidden panel, loses the content.
        "group flex min-w-0 max-w-full flex-col gap-1 rounded-sm outline-none",
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        className,
      )}
    >
      <span className="flex min-w-0 items-center gap-1 text-[0.8125rem] font-medium tracking-tight text-foreground group-hover:underline underline-offset-4 decoration-border">
        <span className="truncate">{source.title}</span>
        <ArrowUpRight className="size-3 shrink-0 text-muted-foreground transition-transform group-hover:-translate-y-px group-hover:translate-x-px" />
      </span>
      <span className="block truncate font-mono text-[0.6875rem] text-muted-foreground">{source.url}</span>
    </a>
  )
}
