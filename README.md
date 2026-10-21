# Fathom

**Find the enterprise questions your buyers can't easily answer.**

A salesperson pastes a prospect's URL. Fathom maps the company's public website,
selectively crawls it, indexes what matters, and reads the deep content for the checkable
claims the company actually published. Each claim is then tested against the pages a buyer
really meets, and the ones a buyer could not reach are ranked. Every completed scan gets a
grounded chatbot on a shareable link.

The whole product runs, and its entire test suite passes, **without a single paid API call**.

```
URL → map site → classify URLs → crawl plan → selective crawl → index
    → company analysis → extract published claims
    → check what a buyer can reach → ranked findings
    → coverage audit → automatic chatbot → shareable demo
```

---

## The idea

Most enterprise buyers abandon an evaluation over a question the vendor has already
answered — in documentation, a help centre article, or a PDF nobody links to. The answer
exists. It just isn't where the buyer is looking.

Fathom finds those. It takes a fact the company published and asks whether a buyer
walking the marketing journey would ever reach it:

```
Question: Can administrators define custom RBAC roles?

BUYER-VISIBLE WEBSITE               DEEP PUBLIC CONTENT
No definitive answer                Definitive answer found
Confidence 0%                       Confidence 89%

                                    "Administrators can define custom RBAC roles
                                     with granular resource permissions... Custom
                                     roles are available on the Enterprise plan."

                                    docs.acme.test/roles

Discoverability gap: 89 points      Friction score: 82
```

That gap is the product.

---

## Stack

| Concern | Choice |
| --- | --- |
| Backend | Rails 8.1, Ruby 4.0 |
| Frontend | Inertia + React 19 + Vite + Tailwind v4 + shadcn/ui |
| Database | PostgreSQL 17 with pgvector (via `neighbor`) |
| Retrieval | Hybrid: pgvector cosine similarity + PostgreSQL full-text search |
| Background jobs | Active Job + Solid Queue |
| AI | RubyLLM 2.0 |
| Crawling | Firecrawl (live) / fixtures (fake) |

No Redis, no Sidekiq, no Python, no separate vector database, no microservices.

---

## Architecture

Domain logic lives in plain Ruby objects under `app/models`, alongside the Active Record
models. There is no `app/services` and no `.call` convention — objects are instantiated
and used through real method names.

```
app/models/
  url.rb                    Url, Url::Classification    normalize, dedupe, classify
  website/map.rb            Website::Map                stage 1: discover URLs
  crawl_plan.rb             CrawlPlan                   stage 2: decide what to fetch
  website/crawl.rb          Website::Crawl              stage 3: fetch selected pages
  corpus/
    cleaner.rb              Corpus::Cleaner             untrusted HTML → text
    chunker.rb              Corpus::Chunker             headings → chunks with provenance
    index.rb                Corpus::Index               stage 4/5: chunk and embed
    search.rb               Corpus::Search              the one retrieval path
    ranking.rb              Corpus::Ranking             reciprocal rank fusion
  ai/
    models.rb               AI::Models                  model roles, not model IDs
    embedder.rb             AI::Embedder                + ::Fake, ::Live
    classifier.rb           AI::Classifier              page types rules cannot name
    analyst.rb              AI::Analyst                 company understanding
    extractor.rb            AI::Extractor               published claims, from deep content
    answerer.rb             AI::Answerer                grounded answering
    responder.rb            AI::Responder               chatbot replies
  coverage_audit.rb         CoverageAudit               questions answered nowhere
  friction_score.rb         FrictionScore               deterministic scoring
  scan/pipeline.rb          Scan::Pipeline              orchestration
  crawler/                  Crawler::Fake / ::Firecrawl / ::Local
```

**Orchestration is stateless.** No job knows what comes after it. Each does its work,
records the result, and asks `Scan::Pipeline` what is left. The database is the source of
truth, so a retried job, a resumed scan and a full rerun all take the same path.

```
mapping → classifying → planning → crawling → processing → embedding → analyzing
       → extracting_claims → checking_visibility → scoring → auditing_coverage
       → creating_chatbot
```

---

## Modes

| Mode | Crawler | AI | Cost |
| --- | --- | --- | --- |
| `fake` (default) | fixtures on disk | deterministic adapters | $0 |
| `local` | self-hosted Firecrawl | local models | $0 |
| `live` | Firecrawl API | OpenAI, or any RubyLLM provider | metered |

**Fake mode never falls back to live mode.** Every outbound request passes
`ExternalRequests.guard!`, which raises in fake mode. An `OPENAI_API_KEY` sitting in your
environment cannot cause a paid request: live spending needs `APP_MODE=live` **and**
`ENABLE_LIVE_AI=true`, both set deliberately.

Fake mode only fakes the parts that cost money. Chunking, database persistence, retrieval
queries, hybrid ranking, source selection, conversation persistence, public routing and
friction scoring are all the real implementations. Fake embeddings are a hashing trick —
each token hashes to a fixed bucket with a stable sign — so vector similarity genuinely
works and the same input always produces the same vector.

---

## Getting started

### Requirements

- Ruby 4.0.5 (see `.ruby-version`)
- Node 24 (see `.node-version`)
- Docker, for PostgreSQL with pgvector

### Setup

```bash
git clone https://github.com/mikailbayram/fathom.git && cd fathom

cp .env.example .env         # defaults are fake mode; no credentials needed
docker compose up -d         # PostgreSQL 17 + pgvector on localhost:5433
bundle install
npm ci
bin/rails db:prepare
```

### Check the environment

```bash
bin/rails app:doctor
```

```
Website Friction Intelligence
────────────────────────────────────────

Application mode
✓ FAKE

External requests
✓ DISABLED

AI token spending
✓ DISABLED

PostgreSQL
✓ Connected

pgvector
✓ Available (0.8.6)

Solid Queue
✓ Schema ready (no worker running; start bin/jobs)

Embedding column
✓ vector(1536) matches text-embedding-3-small

Live integrations
────────────────────────────────────────

○ OPENAI_API_KEY
  Not configured
  Not required in fake mode

○ FIRECRAWL_API_KEY
  Not configured
  Not required in fake mode

Everything required for development is ready.
```

`app:doctor` exits non-zero when something is actually broken, and in live mode it refuses
to pass while a required credential is missing.

### Run it

```bash
bin/dev        # Rails on :3000, Vite on :3036, Solid Queue worker
```

Or separately:

```bash
bin/rails server
bin/vite dev
bin/jobs
```

### Run a fake scan

Open http://localhost:3000, paste `https://acme.test`, and press **Scan**.

Watch the scan walk its stages, open a finding to compare the buyer-visible corpus against
the deep one, then open the demo the scan created and ask it something.

Any other domain works too: the fixture corpus is served with that company's name and
hostnames substituted in, so you can demo the flow against any URL without touching the
network.

### Run the tests

```bash
bin/rails test
```

Zero external calls. The suite installs a socket guard that raises on any
outbound connection, so "CI never spends money" is enforced rather than hoped for. The
end-to-end test in `test/integration/friction_discovery_test.rb` asserts this explicitly.

```bash
bin/rubocop          # lint
bin/brakeman         # security scan
npm run check        # TypeScript
```

---

## Going live

Live mode is opt-in twice over, and `app:doctor` gates it.

### 1. Configure credentials

```
Required now:

[ ] FIRECRAWL_API_KEY
    Purpose: mapping/crawling public websites
    Configure as: FIRECRAWL_API_KEY

[ ] OPENAI_API_KEY
    Purpose: embeddings + AI analysis
    Configure as: OPENAI_API_KEY
```

Put them in `.env` (which is gitignored) or your deployment's secret store. They are never
logged, never printed by `app:doctor`, and never placed in a prompt.

```bash
APP_MODE=live
ENABLE_LIVE_AI=true
OPENAI_API_KEY=sk-...
FIRECRAWL_API_KEY=fc-...
```

### 2. Validate with the smallest safe request

```bash
APP_MODE=live ENABLE_LIVE_AI=true bin/rails app:doctor
APP_MODE=live ENABLE_LIVE_AI=true bin/rails runner 'p Crawler::Firecrawl.new.validate_credential!'
```

### 3. Run a capped smoke test

Do **not** start with a 5,000-page crawl.

```bash
APP_MODE=live ENABLE_LIVE_AI=true MAX_SCAN_PAGES=25 MAX_SCAN_AI_COST_USD=0.50 bin/dev
```

Then verify, in order: mapping, classification, the crawl plan, embedding dimensions,
retrieval, claim extraction, findings, the chatbot, and the source links. Only then raise
the caps.

---

## Model routing

Domain objects ask for a model *role*, never a literal model ID, so changing models — or
benchmarking one against another — is configuration rather than a code change.

```ruby
AI::Models.embedding   # text-embedding-3-small
AI::Models.fast        # gpt-5.6-luna    ambiguous classification, mechanical extraction
AI::Models.analysis    # gpt-5.6-terra   company understanding, extraction, answering
AI::Models.chat        # gpt-5.6-terra   chatbot replies
```

Override per environment:

```
AI_EMBEDDING_MODEL=text-embedding-3-small
AI_FAST_MODEL=gpt-5.6-luna
AI_ANALYSIS_MODEL=gpt-5.6-terra
AI_CHAT_MODEL=gpt-5.6-terra
```

### Providers

`AI_PROVIDER` picks the provider for the fast, analysis and chat roles; it defaults to
`openai` and accepts any provider RubyLLM supports. Embeddings can stay on a different
provider, since the vector column is sized for one embedding model:

```
AI_PROVIDER=openrouter
OPENROUTER_API_KEY=sk-or-...
AI_ANALYSIS_MODEL=anthropic/claude-sonnet-4.5
AI_EMBEDDING_PROVIDER=openai
OPENAI_API_KEY=sk-...
```

`AI_REQUESTS_PER_MINUTE` and `AI_CALL_CONCURRENCY` pace calls to stay under the provider's
rate limits. `.env.example` documents both.

These are configuration, not secrets. There is no automatic escalation to a more expensive
model: if that is ever added it must be explicit, configurable and cost-tracked.

An LLM is never used where deterministic code suffices. URL classification, chunking,
deduplication, retrieval and the friction score are all plain Ruby and PostgreSQL, and
cost zero tokens.

---

## Cost and spending safety

Every AI operation is recorded in `ai_usages` from the provider's own usage metadata —
token counts are never invented, and an unreported cost stays `null` rather than becoming
zero.

```
MAX_SCAN_AI_COST_USD=2.00
MAX_DAILY_AI_COST_USD=10.00
MAX_SCAN_PAGES=5000
```

`SpendingLimit` enforces both budgets before every live call. **In fake mode both budgets
are zero**, which is not a formality: a code path that accidentally reaches a paid provider
fails loudly in development and CI instead of quietly billing someone.

---

## Grounding and prompt-injection

Crawled content is untrusted input, and is treated that way throughout.

- Every grounded prompt delimits source material explicitly and instructs the model to
  ignore instructions found inside it.
- An answer is only accepted if it cites chunk IDs it was actually shown; anything else is
  discarded rather than trusted.
- A finding is never created without source evidence, and the UI always links to the
  original public URL.
- The chatbot says *"I couldn't find a definitive answer in Acme's public website or
  documentation"* rather than filling a gap from model knowledge.
- Rendered content is escaped by React; nothing is injected as HTML.
- Public demo endpoints are rate limited per IP and slug.
- Only public content is fetched. Authentication, CAPTCHAs, access controls and robots
  restrictions are never bypassed.

---

## Configuration

Every tunable setting, and the reasoning behind its default, lives in one place:
`WebsiteIntelligence::Configuration` in `lib/website_intelligence.rb`.

```ruby
config.max_claim_passages = 400      # deep passages read for claims
config.max_claims_per_scan = 120

config.chunk_target_tokens = 750
config.chunk_overlap_tokens = 100

config.semantic_results = 15
config.lexical_results = 15
config.final_retrieval_results = 12

config.minimum_answer_confidence = 0.75
config.minimum_finding_score = 60

config.max_discovered_urls = 50_000
config.max_pages_per_scan = 5_000     # MAX_SCAN_PAGES
```

Most of them read an environment variable, so a deployment overrides them without touching
code. `config/initializers/website_intelligence.rb` is for the settings a deployment wants
to differ — restating a default there just creates a second place to keep in step.

---

## Friction scoring

Deterministic, in plain Ruby, and unit tested. The models supply inputs — confidence,
importance, which sources answered — but never the score itself, because a number a model
invents cannot be audited or tuned.

| Component | Points |
| --- | --- |
| Discoverability gap | 0–40 |
| Buyer importance | 0–20 |
| Source obscurity | 0–15 |
| Technical specificity | 0–15 |
| Answer confidence | 0–10 |
| *Penalty: answer already prominent on the buyer-visible site* | −12 |

The gap carries most of the weight because it is the thing the product exists to measure.
Support does not discriminate: extraction already discarded every claim its own source did
not back up, so by scoring time they are all well supported.

Source obscurity is ordered by where the answer lives: a PDF scores highest, the homepage
lowest.

A question the company answers **nowhere** is a different kind of finding — it has no
source to rate, so it is scored on importance (0–45) and how completely it is absent
(0–35) instead.

---

## The fixture company

`test/fixtures/sites/acme/` is a deterministic company designed to exercise the
proposition. Buyer-visible pages are deliberately vague where the documentation is
deliberately precise.

| Case | Buyer-visible site says | Deep content says |
| --- | --- | --- |
| Custom RBAC | "enterprise-grade access controls" | custom roles, granular permissions, Enterprise plan |
| Webhook retries | nothing | six retries, exponential backoff, dead-letter replay |
| Migration timeline | nothing | four to six weeks, with prerequisites |
| NetSuite sync | "connects to the tools you use" | one-way only; no bidirectional sync |
| Data residency | nothing | EU region, Enterprise plan, request via support |
| RPO / RTO | nothing | RPO 15 minutes, RTO 4 hours (PDF only) |
| SAML SSO *(control)* | stated plainly on pricing | — |
| FedRAMP *(control)* | — | appears nowhere |

The last two are controls: the SSO answer is prominent, so it is penalised and does not
become a finding; FedRAMP is genuinely unanswerable, so the system says so.

---

## Troubleshooting

**`PG::ConnectionBad`** — is the database running? `docker compose up -d`, then
`bin/rails app:doctor`.

**`pgvector extension is not installed`** — the container image must be
`pgvector/pgvector`, not plain `postgres`. `docker compose down -v && docker compose up -d`.

**`chunks.embedding is vector(1536) but ... needs vector(3072)`** — you changed
`AI_EMBEDDING_MODEL`. The column has to match the model. Change it back, or migrate the
column and re-embed.

**Scan stays at "Mapping website"** — no worker is running. Start `bin/jobs`, or use
`bin/dev` which starts one.

**Long-running scans and recovery** — scan activity comes from Solid Queue, not
the time since the progress counter changed. Queued, running, blocked, and
scheduled retry jobs all keep a scan active. Rescan leaves that work alone.
Once the queue records a worker failure and no unfinished jobs remain, Rescan
resumes from saved progress. Start `bin/jobs` first if the worker has stopped;
Solid Queue needs its supervisor running to detect dead workers.

**`ExternalRequestBlocked`** — something tried to reach a provider in fake mode. That is
the guard doing its job; if you meant to go live, set both `APP_MODE=live` and
`ENABLE_LIVE_AI=true`.

**Assets missing in development** — `bin/vite dev` must be running alongside Rails.

**Frontend types failing** — `npm run check` reports them; `tsconfig.json` holds the `@/*`
path alias that shadcn components rely on.
