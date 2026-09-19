# Implementation Progress

Tracking the Website Friction Intelligence MVP against the spec.
Status is honest: **Done** means written and at least smoke-tested; **Written, untested**
means the code exists but no test has run against it yet.

Last updated: 2026-09-18 (fifth pass)

---

## Environment findings (spec §3)

The scaffold did not match the stack the spec assumed. What was actually there:

| Spec assumed | Repository had | Decision |
| --- | --- | --- |
| PostgreSQL + pgvector | SQLite | Switched to Postgres 17 + pgvector via `docker-compose.yml` (port 5433) |
| Existing Inertia frontend | importmap + Hotwire, no `package.json` | Installed Inertia + React 19 + Vite + Tailwind v4 + shadcn/ui; removed Hotwire so there is one frontend stack (confirmed with user) |
| Existing auth / tenancy | Neither | No `User` / `Account` models — spec §8 makes them conditional on existing tenancy |
| RubyLLM | not installed | RubyLLM 2.0.0. API verified against the installed gem, not from memory: `RubyLLM.embed(texts, model:) → .vectors/.tokens/.cost`, `chat.with_schema(hash)` + `message.parsed` |

Versions: Ruby 4.0.5, Rails 8.1.3.1, Node 24.13, Postgres 18 client / 17 server.
Baseline test suite before changes: **0 tests, 0 failures** (nothing to regress).

---

## Phase 0 — Infrastructure — **Done**

- [x] `docker-compose.yml` with `pgvector/pgvector:pg17`
- [x] `config/database.yml` → Postgres, four databases (primary/cache/queue/cable)
- [x] Gemfile: `pg`, `neighbor`, `ruby_llm`, `inertia_rails`, `vite_rails`, `faraday`, `dotenv-rails`
- [x] Inertia + React + TypeScript + Tailwind v4 installed; `config/vite.json` repointed to `app/frontend`
- [x] shadcn/ui configured (`components.json`, `new-york`, neutral base); 15 primitives installed
- [x] Design tokens written in `app/frontend/entrypoints/application.css` (neutral canvas, one accent, restrained radius, light + dark)
- [x] `.env.example` / `.env`, `.env` gitignored
- [x] Solid Queue wired as the development job adapter

## Phase 1 — Schema & models — **Done**

- [x] 14 migrations, all applied; `db/schema.rb` round-trips `vector(1536)`, the generated `tsvector` column, the HNSW index and the GIN index
- [x] Models: Prospect, Scan, DiscoveredUrl, Page, Chunk, CompanyProfile, Question, Finding, FindingSource, Chatbot, Conversation, Message, AiUsage
- [x] Shared vocabulary: `PageTypes`, `CorpusTypes`

## Architecture change — service objects removed

At the user's request, `app/services/` was deleted. Domain logic is now plain objects
under `app/models/`, instantiated and used through real method names rather than a
`.call` entry point. Mapping from the spec's §54 names to what exists:

| Spec name | This codebase |
| --- | --- |
| `Urls::Normalizer` + `Urls::Classifier` | `Url` + `Url::Classification` |
| `Crawling::Client` / `FakeClient` / `FirecrawlClient` | `Crawler::Client` / `Crawler::Fake` / `Crawler::Firecrawl` |
| `AI::EmbeddingProvider` / `AI::FakeEmbeddingProvider` | `AI::Embedder` / `AI::Embedder::Fake` / `::Live` |
| `AI::CompanyAnalyzer` | `AI::Analyst` (+ `::Fake` / `::Live`) |
| `AI::QuestionGenerator` | `AI::Interviewer` (+ `::Fake` / `::Live`) |
| `AI::QuestionAnswerer` | `AI::Answerer` (+ `::Fake` / `::Live`) |
| `Retrieval::Search` | `Corpus::Search` (+ `Corpus::Ranking`, `Corpus::Candidate`) |
| `Scoring::FrictionScorer` | `FrictionScore` |
| `Spending::Guard` | `SpendingLimit` |
| — | `Website::Map`, `Website::Crawl`, `CrawlPlan`, `Corpus::Index`, `Corpus::Chunker`, `AI::Responder`, `Scan::Pipeline` |

## Phase 2 — Domain objects — **Done**

| Object | Status |
| --- | --- |
| `WebsiteIntelligence` config + modes | Done |
| `ExternalRequests`, `SpendingLimit` | Done |
| `Url`, `Url::Classification` | Done, verified |
| `Crawler::Client` / `Fake` / `Firecrawl` / `Local` | Done (Firecrawl v2 API verified against its docs) |
| `Corpus::Cleaner`, `TokenCount`, `Chunker` | Done, verified |
| `Website::Map`, `Website::Crawl`, `CrawlPlan` | Done, verified |
| `AI::Models`, `Lexicon`, `Prompts`, `Client` | Done |
| `AI::Embedder` (+ Fake hashing-trick, Live) | Done, verified |
| `Corpus::Index`, `Corpus::Search`, `Ranking`, `Candidate` | Done, verified |
| `AI::Analyst` / `Interviewer` / `Answerer` / `Responder` | Done, verified |
| `FrictionScore` | Done, verified |
| `Scan::Pipeline` | Done, verified |


## Phase 3 — Jobs & orchestration — **Done**

`PipelineJob` base (failures name their stage), `StartScanJob`, `MapWebsiteJob`,
`BuildCrawlPlanJob`, `CrawlPagesJob`, `ProcessPagesJob`, `EmbedChunksJob`,
`AnalyzeCompanyJob`, `GenerateQuestionsJob`, `AnswerQuestionsJob` → `AnswerQuestionJob`,
`ScoreFindingsJob` → `ScoreFindingJob`, `CreateChatbotJob`, `FinalizeScanJob`.

`ClassifyPagesJob` was not built: classification is deterministic and happens during
mapping, so a separate stage would do nothing. AI classification of genuinely ambiguous
URLs is wired (`Url::Classification#confident?` returns false) but not yet called.

## Phase 4 — Controllers, routes, presenters — **Done**

`ScansController` (new/create/show/status/retry), `ProspectsController`,
`FindingsController`, `DemosController`, `PublicDemosController` (cookie session,
Rails 8 `rate_limit`). `ScanPresenter` / `FindingPresenter` shape Inertia props so no
prompt, model ID or raw analysis reaches the browser.

## Phase 5 — Frontend — **Done**

The `frontend-design` skill was invoked before any page was written, per spec §39.

**Design direction — three voices.** The buyer's question is set in a serif (Newsreader):
a person asking. The machine's own output is Instrument Sans. Anything a reader might
copy or verify — URLs, domains, scores, counts — is IBM Plex Mono. One restrained ink-blue
accent, hairline rules instead of cards, no gradients and no decorative motion.

**The signature comparison communicates the gap through visual weight, not colour.** The
buyer-visible column is grey, its rule dashed, its type muted; the deep column is white,
its rule solid, the answer in serif with the real URL beneath. It reads correctly with the
labels covered and survives being printed in black and white — which also means it never
relies on colour alone to carry status.

Components: `ScanProgress`, `FindingRow`, `ScoreMark`, `SourceLink`, `EvidenceExcerpt`,
`CorpusComparison`, `Metric`, `Eyebrow`, `EmptyState`/`ErrorState`/`FindingsSkeleton`,
`ChatMessage`, `SuggestedQuestion`, `AppLayout`.
Pages: `Scans/New`, `Scans/Index`, `Scans/Show`, `Findings/Show`, `Prospects/Index`,
`Demos/Index`, `Demos/Show`, `Demos/RateLimited`.

TypeScript and the production Vite build are both clean.

### Bugs the browser found that the code did not

1. The public demo posted to `/d/:slug` instead of `/d/:slug/messages` — every question
   404ed. The post path is now a prop from the router rather than derived from
   `window.location`.
2. `"23 URL discovereds"` — the whole phrase was being pluralized instead of the noun.
3. Stages late in the pipeline rendered as complete before they had run, because
   "no unembedded chunks" is vacuously true when there are no chunks. Progress is now
   ordered: nothing past the active stage can report itself complete.
4. The chunk context line (`"Acme Enterprise Deployment Guide -- Recovery objectives"`)
   was being quoted back to readers as if it were prose. `Chunk#body` strips it;
   `Chunk#content` keeps it for retrieval.
5. Weak passages were being quoted alongside strong ones. Counting evidence and quoting
   it are now separate bars (0.6 vs 0.9 of the best passage's coverage).

### Final design review (spec §40)

Every screen was reviewed at 1440px and 390px. What the review changed:

- The header made phones scroll sideways. The nav now scrolls within itself while the
  page does not, so no layout depends on horizontal scrolling.
- On a phone the finding detail's 48px score gutter cost the question a sixth of the
  screen. Score and question now stack below `sm`.
- The discoverability-gap measure was a stray line floating at the right margin. It now
  runs the full width of the comparison it describes.

Checked and unchanged: keyboard focus is visible on every interactive element, a skip
link precedes the nav, status is carried by shape and words as well as colour, all
evidence links to its original public URL, and `prefers-reduced-motion` disables the
animation.

## Phase 6 — Fixture site — **Done**

24 files under `test/fixtures/sites/acme/`, designed to exercise the proposition:

| Case | Buyer-visible says | Deep content says |
| --- | --- | --- |
| Custom RBAC (signature case) | "enterprise-grade access controls" | `docs/roles.md`: custom roles, granular resource permissions, Enterprise plan |
| Webhook retries | nothing | `docs/webhooks.md`: six retries, exponential backoff, dead-letter replay |
| Migration timeline | nothing | `docs/migration.md`: 4–6 weeks, prerequisites |
| NetSuite limitation | "connects to the tools you use" | `developers/netsuite.md`: one-way sync only |
| Hidden plan restriction | nothing | `help/data-residency.md`: EU region, Enterprise only |
| Prominent answer (control) | `pricing.md`: SAML SSO plan is stated plainly | — |
| Unanswerable (control) | — | FedRAMP appears nowhere |

### Verified end-to-end run (fake mode, zero external calls)

```
status=completed
23 URLs discovered -> 19 selected (6 buyer-visible, 13 deep) -> 19 crawled
64 chunks indexed -> 30 questions -> 7 viable findings
2 redundant variants skipped (/de/pricing, /blog/2024/03/...)

 89  RELIABILITY   RPO/RTO             full 92%  buyer 0%   gap 92   pdf
 82  SECURITY      custom RBAC roles   full 89%  buyer 0%   gap 89   docs
 81  API           rate limits / 429   full 86%  buyer 0%   gap 86   docs
 80  INTEGRATIONS  NetSuite one-way    full 99%  buyer 0%   gap 99   developer_docs
 77  API           webhook retries     full 80%  buyer 0%   gap 80   docs
 71  DATA GOV      EU data residency   full 83%  buyer 0%   gap 83   help_center

Controls:
  SAML SSO plan  -> full 73% / buyer 73% -> gap 0 -> penalised -> below_threshold (34)
  FedRAMP        -> unanswerable
```

Three grounding bugs the run exposed, now fixed:

1. A Snowflake question was answered from the NetSuite page. Named third-party systems
   are now required to appear in the evidence (`Terms#satisfied_by?`), not merely
   resemble it.
2. "API rate limits" was answered from a docs index page, because the words naming what
   a page is about lived in a title the section did not own. Chunks now carry their page
   title as context.
3. Weak passages were being quoted alongside strong ones. Supporting evidence must now
   cover at least 60% of what the best passage covers.

## Phase 7 — Tests — **Done**

**176 tests, 632 assertions, 0 failures.** RuboCop clean, Brakeman clean, TypeScript clean.

The suite installs a socket guard that raises on any outbound connection, so "CI never
spends money" is enforced rather than hoped for. `test/integration/friction_discovery_test.rb`
is the spec §59 definition of done and asserts it explicitly.

Covered: URL normalization and deduplication, classification and subdomains, website
mapping, crawl-plan selection, corpus assignment, content deduplication, chunking and
overlap, deterministic fake embeddings, retrieval scoping, semantic and lexical
candidates, hybrid merge and ranking, strict answer validation, unanswerable questions,
source provenance, friction scoring, scan state transitions, job idempotency and retries,
missing credentials, the fake-mode external-request prohibition, failed crawler responses,
failed provider responses, chatbot creation, chatbot retrieval, unsupported-answer
behaviour, source display, conversation persistence, public demo isolation, and public
demo rate limiting.

### Bugs the tests found

1. `insert_all!` writes past the association, so `scan.discovered_urls` kept serving the
   empty collection it had cached during `delete_all`. Both writers now reset.
2. `Corpus::Cleaner` left indentation as a leading space on every line.
3. Chunk overlap never happened for any paragraph larger than the overlap budget — which
   is most documentation paragraphs. Overlap now falls back to trailing sentences.

## Phase 8 — Tooling & docs — **Done**

- `bin/rails app:doctor` — checks mode, spending, PostgreSQL, pgvector, Solid Queue, and
  that `chunks.embedding` matches the configured embedding model. Exits non-zero on a real
  problem, and refuses to pass in live mode while a credential is missing.
- `LiveReadiness` — the controller refuses to start a live scan before its credentials
  exist, rather than failing several stages in.
- README — architecture, the three modes, zero-cost workflow, setup, troubleshooting,
  cost safeguards, and the live smoke-test sequence.
- CI — Postgres + pgvector service, Node, `npm audit`, TypeScript check. The
  `bin/importmap audit` job is gone with importmap; the empty system-test job is gone too.
- Dockerfile — `postgresql-client` and `libpq-dev` in place of `sqlite3`, plus a Node
  stage so the Vite build can run during `assets:precompile`.

---

## Direction changes after the first live run

Three changes were made on the user's instruction after seeing the product work against
a real website. Each replaced something the original spec prescribed.

### 1. Gaps come from analysis, not from a question list

**Was:** generate 25–40 buyer questions from a template bank, answer each twice, compare.
**Now:** read the deep corpus, extract the checkable claims the company actually published,
and test each against the buyer-visible corpus.

The old shape could only find a gap if a question in the list happened to point at it. On
`solution404.io` it generated 30 plausible questions and found nothing. The new shape finds
what a company buried whether or not anyone thought to ask.

| | Question-first | Claim-first |
| --- | --- | --- |
| Candidates | fixed 30 | however many real claims exist |
| Model calls | 60 (2 passes × 30) | ~1 per 8 passages + 1 per claim |
| Cost per scan | ~$1.41 | ~$0.35 |
| Finds the unexpected | no | yes |

`Question` became `Claim`, carrying the source passage, the statement, and a derived
question label. Only the buyer-visible side is now searched: the deep side already has its
answer and its citation.

Scoring was rebalanced for the new shape. Every claim that reaches scoring is already
verified against its source, so support stopped discriminating; the gap now carries 40 of
the 100 points and is defined as how much of a published fact a buyer can reach.

### 2. The demo is realtime

`async` cable only works in-process, and answers are generated in the Solid Queue worker,
so development now uses Solid Cable too. A question is persisted and handed to
`AnswerDemoQuestionJob`; the reply arrives over `ConversationChannel`, scoped to the
visitor's signed cookie so a shared demo link never leaks one visitor's thread to another.

### 3. Retrieval is a tool the chatbot reaches for, not a preamble

The demo is a sales engineer, not a search box. `AI::Responder::Intent` routes greetings,
meta questions ("what can you do?") and off-topic questions without touching the corpus,
and `AI::Responder::CorpusSearchTool` hands the search to the model as a `RubyLLM::Tool`
it calls when an answer actually depends on a fact -- possibly more than once, with better
wording the second time.

Grounding is unchanged and still enforced in code: a reply citing no passage the tool
returned is rejected and becomes an "I can't find that" reply, however plausible it reads.

The single `"I couldn't find a definitive answer"` dead end is gone. There are now four
distinct replies, each decided by what actually happened:

| Situation | Reply |
| --- | --- |
| Greeting or small talk | Greets, names what the documentation covers. No search, no model call. |
| Asked about itself | Explains what it is, from that scan's real topics. |
| Not about this company | Declines, redirects to what it does cover. |
| About the company, unpublished | Says so, offers the nearest documentation, points at their team. |

Verified live: "hi" cost nothing, a real question searched and cited correctly, and a
follow-up about a limit the docs omit said so rather than inventing one. Probe cost $0.007.

### 4. The demo converses

It carries the last six turns, so "and on which plan?" resolves against the previous
question, and it composes prose instead of pasting passages back. Grounding is unchanged:
it still answers only from the corpus and still shows every source.

## Performance work

The demo was reported as laggy, and it was, for three measurable reasons:

| Cause | Was | Now |
| --- | --- | --- |
| Progress polling | 22 SQL queries per poll, every 1.5s | 12, from one snapshot (`Pipeline::Facts`) |
| Solid Cable | polling the database 10×/second per connection | 2×/second |
| Demo preview | an iframe booting a second copy of the whole app | the same chat component, inline |

The chat also hung outright inside a lead: the Action Cable connection authenticates with
the visitor cookie, which only the public demo controller set, so the subscription was
rejected at mount and the reply was generated and delivered to nobody. The cookie is now
set by `VisitorSession` wherever a demo is rendered.

## Open items / risks

- ~~`Chatbot#public` may trip `DangerousAttributeError`~~ — it does not. `public?` works,
  column kept as the spec names it.
- `gpt-5.6-luna` / `gpt-5.6-terra` are not in RubyLLM's model registry, so live calls pass
  `assume_model_exists: true`. Intentional — the spec fixes those IDs.
- **Record/replay (spec §50) is not built.** The spec marks it secondary and says it must
  not delay the MVP. Fake mode already covers the development workflow it exists to serve.
- **Live smoke test: done.** `solution404.io` completed for **$0.26**. It exposed three
  integration bugs that only a real call could find: Faraday silently dropped the `/v2`
  prefix (every Firecrawl request 404ed), RubyLLM requires an explicit `provider:` alongside
  `assume_model_exists`, and 21 of 25 URLs were discarded because the site's paths are
  Norwegian and the classification rules are English.
- **AI classification of ambiguous URLs is now wired and used** (`AI::Classifier`, the
  `classifying` stage), which was the fix for that third bug. Unrecognised paths also now
  default to `marketing` rather than being discarded.
- **The fake extractor is lexicon-driven**, so in fake mode it finds only claims whose
  topic appears in `AI::Lexicon`. The live extractor has no such limit. This is the main
  place fake and live behaviour genuinely differ.
- **Chat retrieval recall.** In the live probe, "how many custom roles can we define?"
  was answered "the documentation does not state a maximum" when `docs/roles.md` does say
  "up to 50". The bot was honest about what it was shown; the search simply did not surface
  the Limits passage. Worth a reranking pass before this is put in front of a prospect.
- **Scoring thresholds are calibrated against one fixture.** `minimum_finding_score = 60`
  separates the acme corpus cleanly; it has not been tuned against a real docs site.
