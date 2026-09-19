import { Clock3 } from "lucide-react"
import { cn } from "@/lib/utils"
import type { SearchEffort as Effort } from "@/types"

/**
 * How hard a buyer would have to work to reach this answer.
 *
 * A band, never a count of minutes. Where a fact sits on a website is knowable;
 * how long one person spends hunting for it is not, and "6 min" computed from
 * path segments reads as a measurement when it is really an opinion with
 * decimal places. The band is the same opinion at the precision we have.
 *
 * Deliberately monochrome: the Findability badge beside it already carries the
 * verdict in colour, and a second coloured chip would read as a second verdict
 * rather than as the cost of the first one.
 */
export function SearchEffort({ effort, className }: { effort: Effort; className?: string }) {
  return (
    <span
      title={effort.path}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full border border-border px-2 py-0.5 text-[0.75rem] font-medium tracking-tight text-muted-foreground",
        className,
      )}
    >
      <Clock3 className="size-3 shrink-0" aria-hidden="true" />
      <span aria-hidden="true">{effort.label}</span>
      <span className="sr-only">
        Estimated time a human would search for this: {effort.label}. {effort.path}
      </span>
    </span>
  )
}
