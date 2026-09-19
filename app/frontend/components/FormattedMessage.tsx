import { Fragment } from "react"

/**
 * Renders a chat reply with a deliberately tiny formatting vocabulary:
 * paragraphs, bullet and numbered lists, bold, and inline code.
 *
 * Not a markdown library. Everything here is built from React text nodes, so
 * nothing the model writes -- and nothing it might have copied out of a crawled
 * page -- can become markup. Links are pointedly absent: a model-authored URL is
 * exactly the thing this product must never render, and the sources shown
 * beneath every answer are the verified ones.
 */
type Block =
  | { type: "paragraph"; lines: string[] }
  | { type: "bullets"; items: string[] }
  | { type: "numbers"; items: string[] }

const BULLET = /^\s*[-*•]\s+(.*)$/
const NUMBERED = /^\s*\d+[.)]\s+(.*)$/

function parse(content: string): Block[] {
  const blocks: Block[] = []

  for (const raw of content.trim().split(/\n{2,}/)) {
    const lines = raw.split("\n").map((line) => line.trim()).filter(Boolean)
    if (lines.length === 0) continue

    if (lines.every((line) => BULLET.test(line))) {
      blocks.push({ type: "bullets", items: lines.map((line) => line.replace(BULLET, "$1")) })
    } else if (lines.every((line) => NUMBERED.test(line))) {
      blocks.push({ type: "numbers", items: lines.map((line) => line.replace(NUMBERED, "$1")) })
    } else {
      // A list that starts mid-block still reads as a list.
      const firstItem = lines.findIndex((line) => BULLET.test(line) || NUMBERED.test(line))
      if (firstItem > 0) {
        blocks.push({ type: "paragraph", lines: lines.slice(0, firstItem) })
        const rest = lines.slice(firstItem)
        const numbered = NUMBERED.test(rest[0])
        blocks.push({
          type: numbered ? "numbers" : "bullets",
          items: rest.map((line) => line.replace(numbered ? NUMBERED : BULLET, "$1")),
        })
      } else {
        blocks.push({ type: "paragraph", lines })
      }
    }
  }

  return blocks
}

/** **bold** and `code`, as text nodes. Anything else stays literal. */
function inline(text: string) {
  const parts = text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g)

  return parts.map((part, index) => {
    if (part.startsWith("**") && part.endsWith("**") && part.length > 4) {
      return (
        <strong key={index} className="font-medium text-foreground">
          {part.slice(2, -2)}
        </strong>
      )
    }
    if (part.startsWith("`") && part.endsWith("`") && part.length > 2) {
      return (
        <code key={index} className="rounded bg-muted px-1 py-0.5 font-mono text-[0.8125em]">
          {part.slice(1, -1)}
        </code>
      )
    }
    return <Fragment key={index}>{part}</Fragment>
  })
}

export function FormattedMessage({ content }: { content: string }) {
  const blocks = parse(content)

  return (
    <div className="space-y-2.5 text-[0.875rem] leading-relaxed text-foreground">
      {blocks.map((block, index) => {
        if (block.type === "paragraph") {
          return <p key={index}>{inline(block.lines.join(" "))}</p>
        }

        const items = block.items.map((item, i) => (
          <li key={i} className="pl-1">
            {inline(item)}
          </li>
        ))

        return block.type === "bullets" ? (
          <ul key={index} className="list-disc space-y-1 pl-4 marker:text-muted-foreground">
            {items}
          </ul>
        ) : (
          <ol key={index} className="list-decimal space-y-1 pl-4 marker:text-muted-foreground">
            {items}
          </ol>
        )
      })}
    </div>
  )
}
