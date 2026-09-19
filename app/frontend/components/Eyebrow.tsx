import { cn } from "@/lib/utils"

/** A small-caps mono label. The machine annotating its own output. */
export function Eyebrow({
  children,
  mono = false,
  className,
}: {
  children: React.ReactNode
  /** Use for units, statuses and categories -- things the machine measured. */
  mono?: boolean
  className?: string
}) {
  return (
    <span className={cn(mono ? "label-mono uppercase" : "eyebrow", "text-muted-foreground", className)}>
      {children}
    </span>
  )
}
