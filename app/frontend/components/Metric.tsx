import { cn } from "@/lib/utils"

/**
 * A number and what it counts. Deliberately not a dashboard tile: metrics are
 * secondary to the findings, so they read as a line of figures, not as boxes.
 */
export function Metric({
  value,
  label,
  className,
}: {
  value: number | string
  label: string
  className?: string
}) {
  return (
    <div className={cn("flex flex-col gap-0.5", className)}>
      <span className="text-[0.9375rem] font-medium leading-none tabular tracking-tight text-foreground">
        {typeof value === "number" ? value.toLocaleString() : value}
      </span>
      <span className="text-[0.8125rem] leading-none text-muted-foreground">{label}</span>
    </div>
  )
}

export function MetricRow({ children }: { children: React.ReactNode }) {
  return <div className="flex flex-wrap items-end gap-x-10 gap-y-4">{children}</div>
}
