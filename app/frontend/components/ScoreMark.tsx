import { cn } from "@/lib/utils"

/**
 * The friction score. Visible, weighted, and not gamified: no badge, no colour
 * ramp, no trophy. A number in a fixed gutter, with a hairline underneath whose
 * width is the score.
 */
export function ScoreMark({ score, className }: { score: number; className?: string }) {
  return (
    <div className={cn("w-11 shrink-0", className)}>
      <div className="text-[1.375rem] font-medium leading-none tabular tracking-tighter text-foreground">{score}</div>
      <div className="mt-2 h-px w-full bg-border" aria-hidden="true">
        <div className="h-px bg-foreground/70" style={{ width: `${Math.max(score, 4)}%` }} />
      </div>
      <span className="sr-only">Friction score {score} out of 100</span>
    </div>
  )
}
