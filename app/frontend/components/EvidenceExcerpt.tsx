import { cn } from "@/lib/utils"

/**
 * Quoted source material, visually distinct from anything generated.
 *
 * A reader has to be able to tell at a glance what the company published from
 * what we concluded, so quoted text sits behind a rule and never shares
 * styling with our own prose.
 */
export function EvidenceExcerpt({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <blockquote
      className={cn(
        "border-l-2 border-border bg-muted/40 py-2.5 pl-4 pr-3 text-[0.8125rem] leading-relaxed text-foreground/85",
        className,
      )}
    >
      {children}
    </blockquote>
  )
}
