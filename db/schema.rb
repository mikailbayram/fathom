# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_19_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "vector"

  create_table "ai_usages", force: :cascade do |t|
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.decimal "estimated_cost", precision: 12, scale: 6
    t.integer "input_tokens"
    t.string "model", null: false
    t.string "operation", null: false
    t.integer "output_tokens"
    t.string "provider", null: false
    t.bigint "scan_id"
    t.index ["conversation_id"], name: "index_ai_usages_on_conversation_id"
    t.index ["created_at"], name: "index_ai_usages_on_created_at"
    t.index ["scan_id", "created_at"], name: "index_ai_usages_on_scan_id_and_created_at"
    t.index ["scan_id"], name: "index_ai_usages_on_scan_id"
  end

  create_table "chatbots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.boolean "public", default: true, null: false
    t.bigint "scan_id", null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.text "system_prompt"
    t.datetime "updated_at", null: false
    t.index ["scan_id"], name: "index_chatbots_on_scan_id", unique: true
    t.index ["slug"], name: "index_chatbots_on_slug", unique: true
  end

  create_table "chunks", force: :cascade do |t|
    t.text "content", null: false
    t.string "corpus_type", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.datetime "embedded_at"
    t.vector "embedding", limit: 1536
    t.string "embedding_model"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "page_id", null: false
    t.integer "position", default: 0, null: false
    t.bigint "scan_id", null: false
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, content)", stored: true
    t.integer "token_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["page_id", "position"], name: "index_chunks_on_page_id_and_position", unique: true
    t.index ["page_id"], name: "index_chunks_on_page_id"
    t.index ["scan_id", "corpus_type"], name: "index_chunks_on_scan_id_and_corpus_type"
    t.index ["scan_id"], name: "index_chunks_on_scan_id"
    t.index ["search_vector"], name: "index_chunks_on_search_vector", using: :gin
  end

  create_table "claims", force: :cascade do |t|
    t.float "buyer_importance", default: 0.5, null: false
    t.string "buyer_persona"
    t.string "category", default: "security_compliance", null: false
    t.bigint "chunk_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.text "question_text", null: false
    t.text "rationale"
    t.bigint "scan_id", null: false
    t.text "statement"
    t.string "status", default: "pending", null: false
    t.float "support", default: 0.0, null: false
    t.string "topic"
    t.datetime "updated_at", null: false
    t.index ["chunk_id"], name: "index_claims_on_chunk_id"
    t.index ["scan_id", "category"], name: "index_claims_on_scan_id_and_category"
    t.index ["scan_id", "statement"], name: "index_claims_on_scan_id_and_statement", unique: true
    t.index ["scan_id", "status"], name: "index_claims_on_scan_id_and_status"
    t.index ["scan_id"], name: "index_claims_on_scan_id"
  end

  create_table "company_profiles", force: :cascade do |t|
    t.jsonb "buyer_personas", default: [], null: false
    t.string "company_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "enterprise_concerns", default: [], null: false
    t.jsonb "enterprise_features", default: [], null: false
    t.jsonb "integrations", default: [], null: false
    t.string "product_category"
    t.jsonb "products", default: [], null: false
    t.jsonb "raw_analysis", default: {}, null: false
    t.bigint "scan_id", null: false
    t.datetime "updated_at", null: false
    t.index ["scan_id"], name: "index_company_profiles_on_scan_id", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "chatbot_id", null: false
    t.datetime "created_at", null: false
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["chatbot_id", "session_id"], name: "index_conversations_on_chatbot_id_and_session_id", unique: true
    t.index ["chatbot_id"], name: "index_conversations_on_chatbot_id"
  end

  create_table "discovered_urls", force: :cascade do |t|
    t.text "canonical_url", null: false
    t.string "corpus_type", default: "unknown", null: false
    t.string "crawl_error"
    t.datetime "crawled_at"
    t.datetime "created_at", null: false
    t.string "host", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "page_type", default: "other", null: false
    t.text "path", null: false
    t.integer "priority", default: 0, null: false
    t.bigint "scan_id", null: false
    t.boolean "selected_for_crawl", default: false, null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.text "url", null: false
    t.index ["scan_id", "canonical_url"], name: "index_discovered_urls_on_scan_id_and_canonical_url", unique: true
    t.index ["scan_id", "crawled_at"], name: "index_discovered_urls_on_scan_id_and_crawled_at"
    t.index ["scan_id", "priority"], name: "index_discovered_urls_on_scan_id_and_priority"
    t.index ["scan_id", "selected_for_crawl"], name: "index_discovered_urls_on_scan_id_and_selected_for_crawl"
    t.index ["scan_id"], name: "index_discovered_urls_on_scan_id"
  end

  create_table "finding_sources", force: :cascade do |t|
    t.bigint "chunk_id", null: false
    t.string "corpus_type", default: "deep", null: false
    t.datetime "created_at", null: false
    t.bigint "finding_id", null: false
    t.boolean "is_primary", default: false, null: false
    t.text "quoted_excerpt"
    t.float "relevance_score", default: 0.0, null: false
    t.datetime "updated_at", null: false
    t.index ["chunk_id"], name: "index_finding_sources_on_chunk_id"
    t.index ["finding_id", "chunk_id"], name: "index_finding_sources_on_finding_id_and_chunk_id", unique: true
    t.index ["finding_id"], name: "index_finding_sources_on_finding_id"
  end

  create_table "findings", force: :cascade do |t|
    t.text "answer"
    t.float "answer_confidence", default: 0.0, null: false
    t.float "buyer_importance", default: 0.0, null: false
    t.text "buyer_visible_answer"
    t.float "buyer_visible_confidence", default: 0.0, null: false
    t.bigint "claim_id", null: false
    t.datetime "created_at", null: false
    t.float "discoverability_score", default: 0.0, null: false
    t.integer "friction_score", default: 0, null: false
    t.float "full_corpus_confidence", default: 0.0, null: false
    t.string "kind", default: "buried", null: false
    t.bigint "scan_id", null: false
    t.jsonb "score_breakdown", default: {}, null: false
    t.string "search_effort"
    t.text "search_path"
    t.string "source_depth"
    t.string "source_type"
    t.string "status", default: "pending", null: false
    t.string "topic"
    t.datetime "updated_at", null: false
    t.text "why_it_matters"
    t.index ["claim_id"], name: "index_findings_on_claim_id", unique: true
    t.index ["scan_id", "friction_score"], name: "index_findings_on_scan_id_and_friction_score"
    t.index ["scan_id", "kind"], name: "index_findings_on_scan_id_and_kind"
    t.index ["scan_id", "status"], name: "index_findings_on_scan_id_and_status"
    t.index ["scan_id"], name: "index_findings_on_scan_id"
  end

  create_table "handoffs", force: :cascade do |t|
    t.text "answer"
    t.datetime "answered_at"
    t.bigint "chatbot_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.text "question", null: false
    t.string "status", default: "waiting", null: false
    t.datetime "updated_at", null: false
    t.string "visitor_email"
    t.index ["chatbot_id", "status"], name: "index_handoffs_on_chatbot_id_and_status"
    t.index ["chatbot_id"], name: "index_handoffs_on_chatbot_id"
    t.index ["conversation_id"], name: "index_handoffs_on_conversation_id"
  end

  create_table "leads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "website_url", null: false
    t.index ["domain"], name: "index_leads_on_domain", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "role", null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "pages", force: :cascade do |t|
    t.text "canonical_url", null: false
    t.text "content"
    t.string "content_hash", null: false
    t.string "corpus_type", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.integer "depth", default: 0, null: false
    t.bigint "discovered_url_id", null: false
    t.integer "http_status"
    t.boolean "indexed", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "page_type", default: "other", null: false
    t.bigint "scan_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.text "url", null: false
    t.integer "word_count", default: 0, null: false
    t.index ["discovered_url_id"], name: "index_pages_on_discovered_url_id"
    t.index ["scan_id", "canonical_url"], name: "index_pages_on_scan_id_and_canonical_url", unique: true
    t.index ["scan_id", "content_hash"], name: "index_pages_on_scan_id_and_content_hash", unique: true
    t.index ["scan_id", "corpus_type"], name: "index_pages_on_scan_id_and_corpus_type"
    t.index ["scan_id"], name: "index_pages_on_scan_id"
  end

  create_table "scans", force: :cascade do |t|
    t.integer "chunks_count", default: 0, null: false
    t.integer "claims_count", default: 0, null: false
    t.datetime "claims_extracted_at"
    t.datetime "completed_at"
    t.datetime "coverage_audited_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "failed_at"
    t.string "failed_stage"
    t.integer "findings_count", default: 0, null: false
    t.bigint "lead_id", null: false
    t.string "mode", default: "fake", null: false
    t.integer "pages_crawled", default: 0, null: false
    t.integer "pages_indexed", default: 0, null: false
    t.integer "pages_selected", default: 0, null: false
    t.jsonb "plan_summary", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.datetime "urls_classified_at"
    t.integer "urls_discovered", default: 0, null: false
    t.index ["lead_id", "created_at"], name: "index_scans_on_lead_id_and_created_at"
    t.index ["lead_id"], name: "index_scans_on_lead_id"
    t.index ["status"], name: "index_scans_on_status"
  end

  add_foreign_key "ai_usages", "conversations"
  add_foreign_key "ai_usages", "scans"
  add_foreign_key "chatbots", "scans"
  add_foreign_key "chunks", "pages"
  add_foreign_key "chunks", "scans"
  add_foreign_key "claims", "chunks"
  add_foreign_key "claims", "scans"
  add_foreign_key "company_profiles", "scans"
  add_foreign_key "conversations", "chatbots"
  add_foreign_key "discovered_urls", "scans"
  add_foreign_key "finding_sources", "chunks"
  add_foreign_key "finding_sources", "findings"
  add_foreign_key "findings", "claims"
  add_foreign_key "findings", "scans"
  add_foreign_key "handoffs", "chatbots"
  add_foreign_key "handoffs", "conversations"
  add_foreign_key "messages", "conversations"
  add_foreign_key "pages", "discovered_urls"
  add_foreign_key "pages", "scans"
  add_foreign_key "scans", "leads"
end
