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
        "group inline-flex max-w-full flex-col gap-1 rounded-sm outline-none",
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        className,
      )}
    >
      <span className="flex items-center gap-1 text-[0.8125rem] font-medium tracking-tight text-foreground group-hover:underline underline-offset-4 decoration-border">
        {source.title}
        <ArrowUpRight className="size-3 text-muted-foreground transition-transform group-hover:-translate-y-px group-hover:translate-x-px" />
      </span>
      <span className="truncate font-mono text-[0.6875rem] text-muted-foreground">{source.url}</span>
    </a>
  )
}
