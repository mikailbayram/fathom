import { Link } from "@inertiajs/react"

/**
 * The shell. There is nothing to navigate between: one lead is one project, so
 * the only destinations are the list and a lead.
 */
export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-dvh">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-md focus:bg-foreground focus:px-4 focus:py-2 focus:text-sm focus:text-background"
      >
        Skip to content
      </a>

      <header className="sticky top-0 z-30 border-b border-border bg-background/85 backdrop-blur">
        <div className="mx-auto flex h-14 max-w-6xl items-center gap-3 px-4 sm:px-6">
          <Link
            href="/"
            className="flex shrink-0 items-center gap-2 rounded-md text-[0.875rem] font-semibold tracking-tighter text-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <span className="grid size-5 place-items-center rounded bg-foreground text-[0.625rem] font-bold text-background">
              F
            </span>
            fathom
          </Link>
        </div>
      </header>

      <main id="main" className="mx-auto max-w-6xl px-4 sm:px-6">
        {children}
      </main>
    </div>
  )
}
