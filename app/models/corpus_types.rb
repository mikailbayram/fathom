# The two logical corpora the whole product turns on, plus the two bookkeeping
# values the mapping stage needs before a URL has been judged.
module CorpusTypes
  BUYER_VISIBLE = "buyer_visible"
  DEEP = "deep"
  IGNORED = "ignored"
  UNKNOWN = "unknown"

  ALL = [ BUYER_VISIBLE, DEEP, IGNORED, UNKNOWN ].freeze
  RETRIEVABLE = [ BUYER_VISIBLE, DEEP ].freeze

  def self.label(corpus)
    case corpus
    when BUYER_VISIBLE then "Buyer-visible website"
    when DEEP then "Deep public content"
    else corpus.to_s.humanize
    end
  end
end
