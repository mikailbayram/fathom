import { Check, X } from "lucide-react"
import { cn } from "@/lib/utils"
import type { PipelineStep } from "@/types"

/**
 * Scanning as a research process rather than a spinner.
 *
 * A vertical timeline on one hairline. Completed stages keep what they produced,
 * so the list reads as an account of the work rather than as a loading state.
 */
export function ScanProgress({ steps }: { steps: PipelineStep[] }) {
  return (
    <ol className="relative">
      <div className="absolute bottom-3 left-[5px] top-3 w-px bg-border" aria-hidden="true" />

      {steps.map((step) => (
        <li key={step.stage} className="relative flex gap-4 py-3 pl-0">
          <Marker state={step.state} />

          <div className="min-w-0 flex-1 pt-px">
            <div
              className={cn(
                "text-[0.9375rem] leading-tight",
                step.state === "pending" && "text-muted-foreground",
                step.state === "active" && "font-medium text-foreground",
                step.state === "complete" && "text-foreground",
                step.state === "failed" && "font-medium text-destructive",
              )}
            >
              {step.label}
              {step.state === "active" && <span className="sr-only"> (in progress)</span>}
              {step.state === "failed" && <span className="sr-only"> (failed)</span>}
            </div>

            {step.detail && (
              <div className="mt-1 font-mono text-xs tabular text-muted-foreground">{step.detail}</div>
            )}
          </div>
        </li>
      ))}
    </ol>
  )
}

/** Status is carried by shape as well as colour, never by colour alone. */
function Marker({ state }: { state: PipelineStep["state"] }) {
  if (state === "complete") {
    return (
      <span className="relative z-10 mt-0.5 flex size-[11px] items-center justify-center rounded-full bg-foreground">
        <Check className="size-2 text-background" strokeWidth={3.5} />
      </span>
    )
  }

  if (state === "failed") {
    return (
      <span className="relative z-10 mt-0.5 flex size-[11px] items-center justify-center rounded-full bg-destructive">
        <X className="size-2 text-background" strokeWidth={3.5} />
      </span>
    )
  }

  if (state === "active") {
    return (
      <span className="relative z-10 mt-0.5 flex size-[11px] items-center justify-center">
        <span className="absolute size-[11px] animate-ping rounded-full bg-primary/30" />
        <span className="size-[7px] rounded-full bg-primary ring-4 ring-background" />
      </span>
    )
  }

  return (
    <span className="relative z-10 mt-0.5 size-[11px] rounded-full border border-border bg-background" />
  )
}
