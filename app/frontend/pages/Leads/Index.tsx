import { useEffect, useRef } from "react"
import { useForm, Link, router } from "@inertiajs/react"
import { ArrowRight } from "lucide-react"
import AppLayout from "@/layouts/AppLayout"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { StatusDot, leadState } from "@/components/StatusDot"
import { EmptyState } from "@/components/States"
import { subscribeToScan } from "@/lib/cable"

interface LeadRow {
  id: number
  name: string
  domain: string
  scans_count: number
  status: string | null
  running: boolean
  failed: boolean
  findings_count: number
  claims_count: number
  pages_crawled: number
  scanned_at: string | null
  waiting_for_slot?: boolean
  stopped?: boolean
  stage_label?: string | null
  demo_path: string | null
}

/**
 * One screen: add a lead, or open one. Everything else about a company lives on
 * that company's own page.
 */
export default function Index({
  leads,
  mode,
  live_ready,
  worker_running,
}: {
  leads: LeadRow[]
  mode: string
  live_ready: boolean
  worker_running: boolean
}) {
  const queued = leads.some((lead) => lead.status === "pending")
  // A list of scans that never changes looks like a list of scans that are
  // stuck, which is exactly how several leads end up appearing to share one
  // status.
  useLiveList()
  const form = useForm({ website_url: "" })

  function submit(event: React.FormEvent) {
    event.preventDefault()
    form.post("/leads")
  }

  return (
    <div className="py-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-[1.5rem] font-semibold tracking-tighter text-foreground">Leads</h1>
          <p className="mt-1 text-[0.8125rem] text-muted-foreground">
            One lead, one company. Scan it, read the gaps, share the demo.
          </p>
        </div>

        <ModeBadge mode={mode} liveReady={live_ready} />
      </div>

      <form onSubmit={submit} className="mt-6">
        <label htmlFor="website_url" className="sr-only">
          Company website
        </label>

        <div className="flex flex-col gap-2 sm:flex-row">
          <Input
            id="website_url"
            type="text"
            inputMode="url"
            autoComplete="off"
            spellCheck={false}
            placeholder="https://company.com"
            value={form.data.website_url}
            onChange={(event) => form.setData("website_url", event.target.value)}
            aria-invalid={Boolean(form.errors.website_url)}
            aria-describedby={form.errors.website_url ? "website_url_error" : undefined}
            className="h-10 flex-1 rounded-lg border-input bg-surface px-3.5 font-mono text-[0.8125rem] shadow-xs md:text-[0.8125rem]"
          />
          <Button type="submit" className="h-10 px-4" disabled={form.processing}>
            {form.processing ? "Starting…" : "Scan"}
            <ArrowRight className="size-3.5" />
          </Button>
        </div>

        {form.errors.website_url && (
          <p id="website_url_error" role="alert" className="mt-2 text-[0.8125rem] text-destructive">
            {form.errors.website_url}
          </p>
        )}
      </form>

      {queued && !worker_running && (
        <p
          role="status"
          className="mt-5 rounded-lg border border-border bg-warning/10 px-4 py-3 text-[0.8125rem] leading-relaxed text-foreground"
        >
          <span className="font-medium">A scan is queued but no worker is running.</span> Start one with{" "}
          <code className="rounded bg-muted px-1 py-0.5 font-mono text-[0.75rem]">bin/jobs</code>, or run{" "}
          <code className="rounded bg-muted px-1 py-0.5 font-mono text-[0.75rem]">bin/dev</code> which starts
          everything together.
        </p>
      )}

      {leads.length === 0 ? (
        <div className="mt-8">
          <EmptyState
            title="No leads yet."
            description="Paste a company URL above. We'll map its public content, test enterprise buyer questions against it, and rank the answers that are hardest to find."
          />
        </div>
      ) : (
        <ul className="mt-8 overflow-hidden rounded-lg border border-border bg-surface">
          {leads.map((lead) => (
            <li key={lead.id} className="border-b border-border last:border-b-0">
              <Link
                href={`/leads/${lead.id}`}
                className="flex flex-wrap items-center gap-x-5 gap-y-1.5 px-4 py-3 outline-none transition-colors hover:bg-accent/50 focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset"
              >
                {/* The name takes the whole line on a phone and the counters
                    wrap beneath it. Sharing one line leaves it about sixty
                    pixels, which is enough for "1fac..." and nothing else. */}
                <span className="w-full min-w-0 sm:w-auto sm:flex-1">
                  <span className="block truncate text-[0.875rem] font-medium tracking-tight text-foreground">
                    {lead.name}
                  </span>
                  <span className="block truncate font-mono text-[0.6875rem] text-muted-foreground">{lead.domain}</span>
                </span>

                <StatusDot state={leadState(lead)} label={lead.stage_label} />

                {lead.status === "completed" && (
                  <span className="flex shrink-0 items-baseline gap-5 font-mono text-[0.6875rem] tabular text-muted-foreground">
                    <span>{lead.pages_crawled.toLocaleString()} pages</span>
                    <span>{lead.claims_count} tested</span>
                    <span className="font-medium text-foreground">{lead.findings_count} gaps</span>
                  </span>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/** Refreshes the list while any scan is in flight, and stops when none are. */
/**
 * Reloads the rows when any scan moves.
 *
 * The broadcast says only that something changed; the rows themselves come back
 * through Inertia, so the socket never carries a second copy of the row shape
 * that could drift from the presenter.
 *
 * Coalesced, because a crawl broadcasts once per page and the list only shows
 * counts. Subscribing unconditionally is deliberate: a scan started from
 * another tab has to light this page up too, and there is no running scan here
 * to gate on when it starts.
 */
function useLiveList() {
  const pending = useRef<number | null>(null)

  useEffect(() => {
    const reload = () => {
      if (pending.current !== null) return

      pending.current = window.setTimeout(() => {
        pending.current = null
        router.reload({ only: ["leads", "worker_running"] })
      }, 400)
    }

    const subscription = subscribeToScan(null, { onEvent: reload, onConnected: reload })

    return () => {
      subscription.unsubscribe()
      if (pending.current !== null) window.clearTimeout(pending.current)
    }
  }, [])
}

function ModeBadge({ mode, liveReady }: { mode: string; liveReady: boolean }) {
  const live = mode === "live"

  return (
    <span className="label-mono inline-flex items-center gap-1.5 rounded-full border border-border bg-surface px-2.5 py-1 uppercase text-muted-foreground">
      <span
        aria-hidden="true"
        className={cnDot(live && liveReady ? "bg-positive" : live ? "bg-destructive" : "bg-border-strong")}
      />
      {mode} mode
      {live && !liveReady && " · credentials missing"}
      {!live && " · no external requests"}
    </span>
  )
}

function cnDot(color: string) {
  return `size-1.5 shrink-0 rounded-full ${color}`
}

Index.layout = (page: React.ReactNode) => <AppLayout>{page}</AppLayout>
