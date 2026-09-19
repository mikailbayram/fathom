import { Link } from "@inertiajs/react"
import { cn } from "@/lib/utils"
import { ScoreMark } from "@/components/ScoreMark"
import { SourceLink } from "@/components/SourceLink"
import { Findability } from "@/components/Findability"
import { SearchEffort } from "@/components/SearchEffort"
import type { FindingRow as Finding } from "@/types"

/**
 * One ranked opportunity. A row, not a card: the question is the dominant
 * element and everything else is annotation around it.
 */
export function FindingRow({ finding, index }: { finding: Finding; index: number }) {
  return (
    <article
      className="group animate-in fade-in slide-in-from-bottom-1 fill-mode-backwards border-b border-border py-6 duration-300 first:border-t"
      style={{ animationDelay: `${Math.min(index * 45, 360)}ms` }}
    >
      <div className="flex gap-4 sm:gap-6">
        <ScoreMark score={finding.score} />

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2.5">
            <Findability score={finding.discoverability_gap} kind={finding.kind} domain={finding.primary_source?.host ?? undefined} />
            <SearchEffort effort={finding.search_effort} />
            <span className="label-mono uppercase text-muted-foreground">{finding.category_label}</span>
          </div>

          <h3 className="question mt-2 text-[1.0625rem] leading-snug sm:text-[1.125rem]">
            <Link
              href={`/findings/${finding.id}`}
              className="rounded-sm outline-none hover:underline underline-offset-[6px] decoration-border focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-4 focus-visible:ring-offset-background"
            >
              {finding.question}
            </Link>
          </h3>

          {finding.answer ? (
            <p className="mt-2 max-w-[74ch] text-[0.8125rem] leading-relaxed text-muted-foreground">
              {finding.answer}
            </p>
          ) : (
            <p className="mt-2 max-w-[74ch] text-[0.8125rem] leading-relaxed text-muted-foreground">
              Nothing in the public content we indexed answers this. A buyer asking it has to contact sales.
            </p>
          )}

          {finding.primary_source && (
            <div className="mt-4">
              <div className="label-mono mb-1 uppercase text-muted-foreground">{finding.source_type_label}</div>
              <SourceLink source={finding.primary_source} />
            </div>
          )}

          <dl className="mt-4 flex flex-wrap gap-x-8 gap-y-2.5">
            <Stat label="Matters to buyers" value={finding.buyer_importance_label} />
            <Stat label="Friction score" value={`${finding.score}/100`} mono />
            {finding.topic && <Stat label="Topic" value={finding.topic} />}
          </dl>
        </div>
      </div>
    </article>
  )
}

function Stat({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex flex-col gap-1">
      <dt className="text-[0.75rem] leading-none text-muted-foreground">{label}</dt>
      <dd className={cn("text-[0.8125rem] leading-none text-foreground", mono && "tabular")}>{value}</dd>
    </div>
  )
}
