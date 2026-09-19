import { Link } from "@inertiajs/react"
import { ArrowLeft } from "lucide-react"
import AppLayout from "@/layouts/AppLayout"
import { CorpusComparison } from "@/components/CorpusComparison"
import { EvidenceExcerpt } from "@/components/EvidenceExcerpt"
import { SourceLink } from "@/components/SourceLink"
import { ScoreMark } from "@/components/ScoreMark"
import { Findability } from "@/components/Findability"
import { SearchEffort } from "@/components/SearchEffort"
import { Eyebrow } from "@/components/Eyebrow"
import type { FindingDetail } from "@/types"

export default function Show({ finding }: { finding: FindingDetail }) {
  return (
    <div className="py-12">
      <Link
        href={`/leads/${finding.lead.id}`}
        className="inline-flex items-center gap-1.5 rounded-sm text-[0.8125rem] text-muted-foreground underline-offset-4 outline-none hover:text-foreground hover:underline focus-visible:ring-2 focus-visible:ring-ring"
      >
        <ArrowLeft className="size-3.5" />
        {finding.lead.company}
      </Link>

      {/* On a phone the score sits above the question rather than beside it:
          a 48px gutter costs the question a sixth of the screen. */}
      <header className="mt-8 flex flex-col gap-5 sm:flex-row sm:gap-8">
        <ScoreMark score={finding.score} />

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2.5">
            <Findability score={finding.discoverability_gap} kind={finding.kind} domain={finding.lead.domain} />
            <SearchEffort effort={finding.search_effort} />
            <Eyebrow mono>{finding.category_label}</Eyebrow>
          </div>
          <h1 className="mt-2.5 max-w-[46ch] text-[1.375rem] font-medium leading-snug tracking-tight text-foreground sm:text-[1.625rem]">
            {finding.question}
          </h1>
          <p className="mt-3 text-[0.8125rem] text-muted-foreground">
            {finding.topic && (
              <>
                <span className="text-foreground">{finding.topic}</span>
                <span className="mx-2 text-border">/</span>
              </>
            )}
            {finding.buyer_importance_label.toLowerCase()} buyer importance
          </p>
          <p className="mt-2 max-w-[62ch] text-[0.8125rem] leading-relaxed text-muted-foreground">
            Estimated time a human would search for this:{" "}
            <span className="text-foreground">{finding.search_effort.short}</span>
            {" "}&mdash; {finding.search_effort.path}
          </p>
        </div>
      </header>

      <section className="mt-10" aria-labelledby="comparison-heading">
        <h2 id="comparison-heading" className="sr-only">
          What the buyer-visible site says, compared with what the documentation says
        </h2>

        <CorpusComparison
          domain={finding.lead.domain}
          gap={finding.discoverability_gap}
          buyerVisible={{
            answerable: finding.buyer_visible_answerable,
            confidence: finding.buyer_visible_confidence,
            answer: finding.buyer_visible_answer,
          }}
          deep={{
            answerable: Boolean(finding.answer),
            confidence: finding.answer_confidence,
            answer: finding.answer,
            source: finding.primary_source,
          }}
        />
      </section>

      {finding.why_it_matters && (
        <section className="mt-10 max-w-[74ch]">
          <h2 className="label-mono mb-2.5 uppercase text-muted-foreground">Why this matters</h2>
          {/* Our interpretation, kept clearly apart from anything quoted. */}
          <p className="text-[0.8125rem] leading-relaxed text-muted-foreground">{finding.why_it_matters}</p>
        </section>
      )}

      {finding.supporting_sources.length > 0 && (
        <section className="mt-10">
          <h2 className="label-mono mb-4 uppercase text-muted-foreground">Supporting evidence</h2>

          <ul className="space-y-6">
            {finding.supporting_sources.map((source, index) => (
              <li key={`${source.url}-${index}`} className="border-t border-border pt-5">
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <Eyebrow mono>{source.page_type_label}</Eyebrow>
                  <Eyebrow mono className="text-muted-foreground/70">{source.corpus_label}</Eyebrow>
                </div>

                {source.excerpt && <EvidenceExcerpt className="mt-4">{source.excerpt}</EvidenceExcerpt>}

                <div className="mt-4">
                  <SourceLink source={source} />
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}

Show.layout = (page: React.ReactNode) => <AppLayout>{page}</AppLayout>
