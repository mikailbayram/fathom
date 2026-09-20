import { useEffect, useMemo, useRef, useState } from "react"
import { Link, router } from "@inertiajs/react"
import { ArrowLeft, ArrowUpRight, Check, Copy, RotateCw, Square, Trash2 } from "lucide-react"
import AppLayout from "@/layouts/AppLayout"
import { Button } from "@/components/ui/button"
import { ScanProgress } from "@/components/ScanProgress"
import { FindingRow } from "@/components/FindingRow"
import { EmptyState, ErrorState } from "@/components/States"
import { Metric, MetricRow } from "@/components/Metric"
import { StatusDot, leadState } from "@/components/StatusDot"
import { DemoChat } from "@/components/DemoChat"
import { subscribeToScan } from "@/lib/cable"
import { cn } from "@/lib/utils"
import type { FindingRow as Finding, ScanMetrics, PipelineStep, CompanyProfile, Handoff } from "@/types"

const TABS = [
  { id: "gaps", label: "Gaps" },
  { id: "demo", label: "Demo" },
  { id: "questions", label: "Questions for you" },
  { id: "scan", label: "Scan" },
] as const

type TabId = (typeof TABS)[number]["id"]

interface Demo {
  name: string
  slug: string
  path: string
  public: boolean
  suggested_questions: string[]
  widget_snippet: string
}

interface LeadDetail {
  id: number
  name: string
  domain: string
  website_url: string
  status: string | null
  running: boolean
  failed: boolean
  stalled?: boolean
  waiting_for_slot?: boolean
  stage_label?: string | null
  scans_count: number
  findings_count: number
  claims_found: number
  metrics: ScanMetrics
  profile: CompanyProfile | null
  plan: Record<string, unknown>
  findings: Finding[]
  categories: string[]
  demo: Demo | null
  handoffs: Handoff[]
  waiting_handoffs: number
  mode: string | null
}

interface StatusPayload {
  present: boolean
  running: boolean
  failed: boolean
  stalled?: boolean
  waiting_for_slot?: boolean
  stage_label?: string | null
  failed_stage?: string | null
  failed_stage_label?: string | null
  error_message?: string | null
  status?: string
  metrics?: ScanMetrics
  steps: PipelineStep[]
}

/**
 * Keyed on the lead so navigating between two leads remounts rather than reuses.
 *
 * Every piece of state below is seeded from props with useState, which only
 * reads them on mount -- so without this, opening a second lead would keep
 * showing the first one's scan status, its open tab and its chat.
 */
export default function Show(props: { lead: LeadDetail; status: StatusPayload; tab: TabId }) {
  return <LeadView key={props.lead.id} {...props} />
}

/** One lead, one project: the gaps, the demo and the scan behind them. */
function LeadView({ lead, status, tab }: { lead: LeadDetail; status: StatusPayload; tab: TabId }) {
  const live = useLeadStatus(lead.id, status)
  const [active, setActive] = useState<TabId>(tab)
  // Rendered from the live payload, falling back to the props it was seeded
  // from. Reading these off the props alone is what froze the header: Inertia
  // only re-sends them when the page reloads, which is at the very end.
  const state = live.present ? live : lead
  const complete = (live.present ? live.status : lead.status) === "completed"
  const metrics = live.metrics ?? lead.metrics

  return (
    <div className="py-8">
      <Link
        href="/"
        className="inline-flex items-center gap-1.5 rounded-sm text-[0.8125rem] text-muted-foreground underline-offset-4 outline-none hover:text-foreground hover:underline focus-visible:ring-2 focus-visible:ring-ring"
      >
        <ArrowLeft className="size-3.5" />
        Leads
      </Link>

      <header className="mt-5 flex flex-wrap items-start justify-between gap-5">
        <div className="min-w-0">
          <h1 className="text-[1.625rem] font-semibold leading-none tracking-tighter text-foreground">{lead.name}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1">
            <a
              href={lead.website_url}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 rounded-sm font-mono text-[0.75rem] text-muted-foreground underline-offset-4 outline-none hover:text-foreground hover:underline focus-visible:ring-2 focus-visible:ring-ring"
            >
              {lead.domain}
              <ArrowUpRight className="size-3" />
            </a>
            <StatusDot state={leadState(state)} label={live.stage_label ?? lead.stage_label} />
            {lead.profile?.product_category && (
              <span className="text-[0.75rem] text-muted-foreground">{lead.profile.product_category}</span>
            )}
          </div>
        </div>

        <div className="flex shrink-0 flex-wrap items-center gap-2">
          {/* Stop is offered only while there is something to stop, and sits
              before Rescan so the destructive-ish one is not where the
              habitual click lands. */}
          {state.running && (
            <Button variant="outline" size="sm" onClick={() => router.post(`/leads/${lead.id}/stop`)}>
              <Square className="size-3.5" />
              Stop
            </Button>
          )}

          <Button variant="outline" size="sm" onClick={() => router.post(`/leads/${lead.id}/rescan`)}>
            <RotateCw className="size-3.5" />
            {lead.scans_count === 0 ? "Scan" : state.running ? "Restart" : "Rescan"}
          </Button>

          {lead.scans_count > 0 && (
            <Button
              variant="outline"
              size="sm"
              aria-label="Delete this scan"
              onClick={() => {
                // A browser confirm, because this throws away the pages, the
                // gaps and the demo link, and the work cost real money to
                // produce. Nothing here can put it back.
                if (window.confirm(`Delete this scan of ${lead.name}? Its pages, gaps and demo link go with it.`)) {
                  router.delete(`/leads/${lead.id}/scan`)
                }
              }}
            >
              <Trash2 className="size-3.5" />
              Delete
            </Button>
          )}

          {lead.demo && <CopyLink path={lead.demo.path} />}
        </div>
      </header>

      {live.failed ? (
        <div className="mt-7">
          <ErrorState
            stage={live.failed_stage_label ?? null}
            message={live.error_message ?? null}
            onRetry={() => router.post(`/leads/${lead.id}/rescan`)}
          />
        </div>
      ) : !complete ? (
        <div className="mt-8 max-w-xl">
          {(live.status ?? lead.status) === "stopped" && (
            <p className="mb-5 rounded-lg border border-border bg-muted/50 px-4 py-3 text-[0.8125rem] leading-relaxed text-foreground">
              <span className="font-medium">You stopped this scan.</span> Everything it had already found is below.
              <span className="font-medium"> Rescan</span> picks up from where it left off.
            </p>
          )}
          {live.stalled && (
            <p className="mb-5 rounded-lg border border-border bg-warning-surface px-4 py-3 text-[0.8125rem] leading-relaxed text-foreground">
              <span className="font-medium">This scan has unfinished work.</span> No jobs are queued or running.
              <span className="font-medium"> Rescan</span> resumes from its saved progress.
            </p>
          )}
          {live.present ? (
            <ScanProgress steps={live.steps} />
          ) : (
            <EmptyState title="Not scanned yet." description="Run a scan to map this company's public content." />
          )}
        </div>
      ) : (
        <>
          <div className="mt-7 rounded-lg border border-border bg-surface px-5 py-4">
            <MetricRow>
              <Metric value={metrics.urls_discovered} label="URLs mapped" />
              <Metric value={metrics.pages_crawled} label="pages analyzed" />
              <Metric value={metrics.chunks} label="passages indexed" />
              <Metric value={lead.claims_found} label="facts published" />
              <Metric value={metrics.findings} label="gaps" />
              {metrics.cost && <Metric value={metrics.cost.label} label="cost to run" />}
            </MetricRow>
          </div>

          <nav className="mt-7 flex gap-1 border-b border-border" aria-label="Lead sections">
            {TABS.map((item) => (
              <button
                key={item.id}
                type="button"
                onClick={() => setActive(item.id)}
                aria-current={active === item.id ? "page" : undefined}
                className={cn(
                  "relative -mb-px px-3 py-2 text-[0.8125rem] font-medium tracking-tight transition-colors outline-none",
                  "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset",
                  active === item.id
                    ? "text-foreground after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:bg-foreground"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                {item.label}
                {item.id === "gaps" && lead.findings.length > 0 && (
                  <span className="ml-1.5 font-mono text-[0.6875rem] tabular text-muted-foreground">
                    {lead.findings.length}
                  </span>
                )}
                {item.id === "questions" && lead.waiting_handoffs > 0 && (
                  <span className="ml-1.5 rounded-full bg-brand px-1.5 py-0.5 font-mono text-[0.625rem] tabular text-brand-foreground">
                    {lead.waiting_handoffs}
                  </span>
                )}
              </button>
            ))}
          </nav>

          <div className="mt-6">
            {active === "gaps" && <Gaps lead={lead} />}
            {active === "demo" && <DemoPanel lead={lead} />}
            {active === "questions" && <Questions lead={lead} />}
            {active === "scan" && <ScanPanel lead={lead} steps={live.steps} />}
          </div>
        </>
      )}
    </div>
  )
}

function Gaps({ lead }: { lead: LeadDetail }) {
  const [category, setCategory] = useState<string | null>(null)
  const findings = useMemo(
    () => (category ? lead.findings.filter((f) => f.category === category) : lead.findings),
    [lead.findings, category],
  )

  if (lead.findings.length === 0) {
    return (
      <EmptyState
        title="No strong discoverability gap found."
        description={`We read ${lead.name}'s deep public content and found ${lead.claims_found} enterprise claims, but each one is already reachable from the buyer-facing site.`}
      />
    )
  }

  return (
    <>
      {lead.categories.length > 1 && (
        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filter gaps by category">
          <Chip label="All" active={category === null} onClick={() => setCategory(null)} />
          {lead.categories.map((value) => (
            <Chip
              key={value}
              label={value.replace(/_/g, " ")}
              active={category === value}
              onClick={() => setCategory(value)}
            />
          ))}
        </div>
      )}

      <div className="mt-5">
        {findings.map((finding, index) => (
          <FindingRow key={finding.id} finding={finding} index={index} />
        ))}
      </div>
    </>
  )
}

/**
 * The demo tab shows the real public page in a frame rather than a replica, so
 * what a salesperson previews is exactly what a prospect will open.
 */
function DemoPanel({ lead }: { lead: LeadDetail }) {
  if (!lead.demo) {
    return <EmptyState title="No demo yet." description="A demo is created automatically when a scan completes." />
  }

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-[64ch] text-[0.8125rem] leading-relaxed text-muted-foreground">
          This is the page your prospect opens. It answers only from {lead.name}&rsquo;s own public content and links
          to the source of every answer.
        </p>
        <Button variant="outline" size="sm" asChild>
          <a href={lead.demo.path} target="_blank" rel="noopener noreferrer">
            Open demo
            <ArrowUpRight className="size-3.5" />
          </a>
        </Button>
      </div>

      <EmbedSnippet snippet={lead.demo.widget_snippet} company={lead.name} />

      <div className="mt-4 overflow-hidden rounded-lg border border-border bg-background">
        <div className="flex items-center gap-2 border-b border-border bg-muted/60 px-3 py-2">
          <span className="size-1.5 rounded-full bg-positive" aria-hidden="true" />
          <span className="truncate font-mono text-[0.6875rem] text-muted-foreground">{lead.demo.path}</span>
        </div>
        <div className="flex h-[560px] flex-col px-4 py-4">
          <DemoChat
            company={lead.name}
            slug={lead.demo.slug}
            askPath={`${lead.demo.path}/messages`}
            handoffPath={`${lead.demo.path}/handoffs`}
            suggestedQuestions={lead.demo.suggested_questions}
            initialMessages={[]}
            compact
          />
        </div>
      </div>
    </div>
  )
}

/**
 * Questions the agent could not answer, waiting on a person.
 *
 * This is the other half of the product: the gaps say what the website fails to
 * make findable, and these say what a real buyer asked that it could not answer
 * at all. Answering one posts straight back into that visitor's conversation.
 */
function Questions({ lead }: { lead: LeadDetail }) {
  const waiting = lead.handoffs.filter((handoff) => handoff.status === "waiting")
  const done = lead.handoffs.filter((handoff) => handoff.status !== "waiting")

  if (lead.handoffs.length === 0) {
    return (
      <EmptyState
        title="Nothing waiting on you."
        description={`When the demo can't answer something from ${lead.name}'s public content, the visitor can ask for a person. Those questions land here.`}
      />
    )
  }

  return (
    <div className="space-y-8">
      {waiting.length > 0 && (
        <section>
          <h2 className="label-mono mb-3 uppercase text-muted-foreground">Waiting on you</h2>
          <ul className="space-y-3">
            {waiting.map((handoff) => (
              <li key={handoff.id}>
                <AnswerForm handoff={handoff} />
              </li>
            ))}
          </ul>
        </section>
      )}

      {done.length > 0 && (
        <section>
          <h2 className="label-mono mb-3 uppercase text-muted-foreground">Handled</h2>
          <ul className="overflow-hidden rounded-lg border border-border bg-surface">
            {done.map((handoff) => (
              <li key={handoff.id} className="border-b border-border px-4 py-3 last:border-b-0">
                <p className="text-[0.8125rem] font-medium tracking-tight text-foreground">{handoff.question}</p>
                {handoff.answer && (
                  <p className="mt-1 text-[0.8125rem] leading-relaxed text-muted-foreground">{handoff.answer}</p>
                )}
                <p className="mt-1.5 label-mono uppercase text-muted-foreground">{handoff.status}</p>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}

function AnswerForm({ handoff }: { handoff: Handoff }) {
  const [answer, setAnswer] = useState("")

  return (
    <div className="rounded-lg border border-border bg-surface p-4">
      <p className="text-[0.875rem] font-medium leading-snug tracking-tight text-foreground">{handoff.question}</p>
      <p className="mt-1 text-[0.75rem] text-muted-foreground">
        {handoff.visitor_email ? `From ${handoff.visitor_email}` : "No email left"} ·{" "}
        {new Date(handoff.asked_at).toLocaleString()}
      </p>

      <form
        onSubmit={(event) => {
          event.preventDefault()
          if (answer.trim()) router.put(`/handoffs/${handoff.id}`, { answer })
        }}
        className="mt-3"
      >
        <label htmlFor={`answer-${handoff.id}`} className="sr-only">
          Your answer
        </label>
        <textarea
          id={`answer-${handoff.id}`}
          value={answer}
          onChange={(event) => setAnswer(event.target.value)}
          rows={3}
          placeholder="Answer this, and it appears in their conversation straight away."
          className="w-full rounded-lg border border-input bg-background px-3 py-2 text-[0.8125rem] leading-relaxed text-foreground outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/25"
        />
        <div className="mt-2 flex items-center gap-2">
          <Button type="submit" size="sm" disabled={!answer.trim()}>
            Send answer
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => router.put(`/handoffs/${handoff.id}`, { dismiss: "1" })}
          >
            Dismiss
          </Button>
        </div>
      </form>
    </div>
  )
}

/**
 * The snippet a salesperson pastes into a prospect's own browser console, so
 * the demo appears on the prospect's own website. Seeing your own site answer a
 * question your own site could not answer is a better argument than a deck.
 */
function EmbedSnippet({ snippet, company }: { snippet: string; company: string }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(snippet)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      setCopied(false)
    }
  }

  return (
    <div className="mt-5 rounded-lg border border-border bg-surface p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="text-[0.8125rem] font-medium tracking-tight text-foreground">Show it on their own site</h3>
          <p className="mt-0.5 text-[0.75rem] text-muted-foreground">
            Paste this into the console on {company}&rsquo;s website. The bot appears in the corner of their page.
          </p>
        </div>
        <Button size="sm" variant="outline" onClick={copy}>
          {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
          {copied ? "Copied" : "Copy snippet"}
        </Button>
      </div>

      <pre className="mt-3 overflow-x-auto rounded-md border border-border bg-muted/60 px-3 py-2">
        <code className="font-mono text-[0.6875rem] text-foreground">{snippet}</code>
      </pre>
    </div>
  )
}

function ScanPanel({ lead, steps }: { lead: LeadDetail; steps: PipelineStep[] }) {
  const plan = lead.plan as Record<string, number>

  return (
    <div className="grid gap-8 md:grid-cols-2">
      <div>
        <h2 className="label-mono mb-4 uppercase text-muted-foreground">Pipeline</h2>
        <ScanProgress steps={steps} />
      </div>

      <div>
        <h2 className="label-mono mb-4 uppercase text-muted-foreground">Crawl plan</h2>
        <dl className="overflow-hidden rounded-lg border border-border bg-surface">
          {[
            ["URLs discovered", plan.discovered],
            ["Eligible after filtering", plan.eligible],
            ["High priority", plan.high_priority],
            ["Selected for crawl", plan.selected],
            ["Buyer-visible selected", plan.buyer_visible_selected],
            ["Deep content selected", plan.deep_selected],
            ["Skipped as redundant", plan.skipped_redundant_variants],
            ["Skipped as low value", plan.skipped_offsite_or_low_value],
          ]
            .filter(([, value]) => value !== undefined)
            .map(([label, value]) => (
              <div key={String(label)} className="flex items-baseline justify-between border-b border-border px-4 py-2.5 last:border-b-0">
                <dt className="text-[0.8125rem] text-muted-foreground">{label}</dt>
                <dd className="font-mono text-[0.8125rem] tabular text-foreground">{Number(value).toLocaleString()}</dd>
              </div>
            ))}
        </dl>

        {lead.profile && (
          <>
            <h2 className="label-mono mb-3 mt-8 uppercase text-muted-foreground">What we understood</h2>
            <div className="space-y-3 rounded-lg border border-border bg-surface p-4">
              <p className="text-[0.8125rem] leading-relaxed text-muted-foreground">{lead.profile.description}</p>
              <TagList label="Integrations" values={lead.profile.integrations} />
              <TagList label="Enterprise concerns" values={lead.profile.enterprise_concerns} />
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function TagList({ label, values }: { label: string; values: string[] }) {
  if (values.length === 0) return null

  return (
    <div>
      <div className="label-mono mb-1.5 uppercase text-muted-foreground">{label}</div>
      <div className="flex flex-wrap gap-1">
        {values.map((value) => (
          <span key={value} className="rounded border border-border bg-muted/60 px-1.5 py-0.5 font-mono text-[0.6875rem] text-foreground">
            {value}
          </span>
        ))}
      </div>
    </div>
  )
}

function Chip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        "label-mono rounded-md border px-2.5 py-1 uppercase transition-colors outline-none",
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        active
          ? "border-foreground bg-foreground text-background"
          : "border-border bg-surface text-muted-foreground hover:border-border-strong hover:text-foreground",
      )}
    >
      {label}
    </button>
  )
}

function CopyLink({ path }: { path: string }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(new URL(path, window.location.origin).toString())
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      setCopied(false)
    }
  }

  return (
    <Button size="sm" onClick={copy}>
      {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
      {copied ? "Copied" : "Copy demo link"}
    </Button>
  )
}

/**
 * The scan's status, pushed over the socket.
 *
 * Nothing is polled. The scan broadcasts on every stage change and on every
 * counter refresh -- which is once per page crawled and once per batch indexed
 * -- so a timer asking "anything yet?" would only ever arrive after the answer
 * had already been sent.
 *
 * The one fetch left is the resync on connect. Action Cable reconnects by
 * itself after a drop, but it does not replay what it missed, so the state is
 * read back once each time the socket comes up.
 */
function useLeadStatus(leadId: number, initial: StatusPayload) {
  const [status, setStatus] = useState(initial)
  // Props arriving from a reload are newer than anything held here, and the
  // seed is only read on mount, so they have to be taken explicitly.
  useEffect(() => setStatus(initial), [initial])

  const finished = useRef(false)

  useEffect(() => {
    if (!initial.running) return

    finished.current = false
    let cancelled = false

    // One reload when the scan ends, however the news arrives: the findings,
    // the demo and the cost are props, and only a reload brings them.
    const apply = (next: StatusPayload) => {
      if (cancelled) return

      setStatus(next)
      if (next.running || finished.current) return

      finished.current = true
      router.reload()
    }

    const resync = async () => {
      try {
        const response = await fetch(`/leads/${leadId}/status`, { headers: { Accept: "application/json" } })
        if (response.ok) apply(await response.json())
      } catch {
        // The socket is up; the next broadcast carries the same thing.
      }
    }

    const subscription = subscribeToScan<StatusPayload>(leadId, { onEvent: apply, onConnected: resync })

    return () => {
      cancelled = true
      subscription.unsubscribe()
    }
  }, [leadId, initial.running])

  return status
}

Show.layout = (page: React.ReactNode) => <AppLayout>{page}</AppLayout>
