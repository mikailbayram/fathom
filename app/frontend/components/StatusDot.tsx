import { cn } from "@/lib/utils"

type State = "queued" | "running" | "waiting" | "stalled" | "complete" | "failed" | "idle"

const COPY: Record<State, string> = {
  queued: "Queued",
  running: "Scanning",
  waiting: "Waiting for a slot",
  stalled: "Stopped",
  complete: "Ready",
  failed: "Failed",
  idle: "Not scanned",
}

/**
 * Status, carried by a word as well as a colour. The dot is an accent on the
 * label, never the label itself.
 *
 * `label` replaces the word for a running scan, so a row can say which stage it
 * is in rather than saying "Scanning" for eleven minutes. The colour still
 * comes from the state, so the override cannot contradict the dot.
 */
export function StatusDot({ state, label, className }: { state: State; label?: string | null; className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-1.5 text-[0.75rem] text-muted-foreground", className)}>
      <span
        aria-hidden="true"
        className={cn(
          "size-1.5 shrink-0 rounded-full",
          state === "queued" && "bg-warning",
          state === "running" && "animate-pulse bg-brand",
          state === "waiting" && "bg-warning",
          state === "stalled" && "bg-warning",
          state === "complete" && "bg-positive",
          state === "failed" && "bg-destructive",
          state === "idle" && "bg-border-strong",
        )}
      />
      {(state === "running" && label) || COPY[state]}
    </span>
  )
}

export function leadState(lead: {
  running: boolean
  failed: boolean
  stalled?: boolean
  waiting_for_slot?: boolean
  status?: string | null
}): State {
  if (lead.failed) return "failed"
  if (lead.status === "completed") return "complete"
  if (lead.status === "pending") return "queued"
  if (lead.waiting_for_slot) return "waiting"
  if (lead.stalled) return "stalled"
  if (lead.running) return "running"
  return "idle"
}
