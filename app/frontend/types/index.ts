export type StepState = "complete" | "active" | "pending" | "failed"

export interface PipelineStep {
  stage: string
  label: string
  state: StepState
  detail: string | null
}

export interface ScanMetrics {
  urls_discovered: number
  pages_crawled: number
  chunks: number
  claims: number
  findings: number
}

export interface Source {
  title: string
  url: string
  host: string | null
  page_type: string
  page_type_label: string
  corpus_type: string
  corpus_label: string
  excerpt: string | null
}

export interface FindingRow {
  id: number
  /** "buried" = published but unreachable. "missing" = published nowhere. */
  kind: "buried" | "missing"
  score: number
  category: string
  category_label: string
  question: string
  answer: string | null
  topic: string | null
  buyer_importance_label: string
  answer_confidence: number
  buyer_visible_confidence: number
  discoverability_gap: number
  source_type: string
  source_type_label: string
  primary_source: Source | null
}

export interface FindingDetail extends FindingRow {
  why_it_matters: string | null
  buyer_visible_answer: string | null
  buyer_visible_answerable: boolean
  supporting_sources: Source[]
  lead: { id: number; company: string; domain: string }
}

export interface CompanyProfile {
  description: string | null
  product_category: string | null
  integrations: string[]
  enterprise_concerns: string[]
}

export interface ChatSource {
  title: string
  url: string
  page_type: string
  page_type_label: string
  excerpt: string
}

export type MessageKind = "answer" | "greeting" | "meta" | "off_topic" | "overview" | "unavailable" | "human_requested" | "smalltalk" | "nothing_indexed" | "conversational" | "handed_off" | "human"

export interface ChatMessage {
  id: number
  role: "user" | "assistant"
  content: string
  grounded: boolean
  kind: MessageKind
  sources: ChatSource[]
  created_at: string
}

export interface Handoff {
  id: number
  question: string
  visitor_email: string | null
  status: "waiting" | "answered" | "dismissed"
  answer: string | null
  asked_at: string
  answered_at: string | null
}
