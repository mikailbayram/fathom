import { Link } from "@inertiajs/react"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"

/** An empty state that says what to do next, not that there is nothing here. */
export function EmptyState({
  title,
  description,
  action,
}: {
  title: string
  description?: string
  action?: { label: string; href: string }
}) {
  return (
    <div className="border-y border-border py-20 text-center">
      <h2 className="question text-xl text-foreground">{title}</h2>
      {description && (
        <p className="mx-auto mt-3 max-w-[48ch] text-[0.9375rem] leading-relaxed text-muted-foreground">
          {description}
        </p>
      )}
      {action && (
        <Button asChild className="mt-7">
          <Link href={action.href}>{action.label}</Link>
        </Button>
      )}
    </div>
  )
}

/**
 * An error state that names the stage that failed. The application knows which
 * one it was, so "something went wrong" would be a choice, not a limitation.
 */
export function ErrorState({
  stage,
  message,
  onRetry,
}: {
  stage: string | null
  message: string | null
  onRetry?: () => void
}) {
  return (
    <div className="border-y border-border py-12">
      <div className="eyebrow text-destructive">Scan failed</div>
      <h2 className="question mt-3 text-xl text-foreground">
        {stage ? `${stage} did not complete.` : "This scan did not complete."}
      </h2>
      {message && (
        <p className="mt-3 max-w-[70ch] font-mono text-xs leading-relaxed text-muted-foreground">{message}</p>
      )}
      {onRetry && (
        <Button variant="outline" className="mt-7" onClick={onRetry}>
          Retry from this stage
        </Button>
      )}
    </div>
  )
}

/** Loading treatment for the findings list, matching its real proportions. */
export function FindingsSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div>
      {Array.from({ length: rows }).map((_, index) => (
        <div key={index} className="flex gap-8 border-b border-border py-8 first:border-t">
          <Skeleton className="h-7 w-12 shrink-0" />
          <div className="flex-1 space-y-3">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-6 w-[70%]" />
            <Skeleton className="h-4 w-[90%]" />
            <Skeleton className="h-4 w-[45%]" />
          </div>
        </div>
      ))}
    </div>
  )
}
