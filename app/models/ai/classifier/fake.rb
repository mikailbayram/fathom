# frozen_string_literal: true

module AI
  class Classifier
    # Deterministic refinement with no provider behind it.
    #
    # It recognises the handful of non-English path words the fixture and common
    # European sites use, which is enough to exercise the persistence path that
    # the live classifier shares.
    class Fake < Classifier
      HINTS = {
        "docs" => %w[dokumentasjon documentacion dokumentation guide handbuch],
        "developer_docs" => %w[api sdk utvikler entwickler],
        "support" => %w[support hjelp hilfe soporte kontakt contact],
        "pricing" => %w[pris preise precios tarif],
        "product" => %w[produkt producto tjenester services losninger],
        "careers" => %w[jobb karriere carriere empleo]
      }.freeze

      def classify(batch)
        batch.to_h do |discovered_url|
          haystack = discovered_url.path.downcase
          match = HINTS.find { |_, words| words.any? { |word| haystack.include?(word) } }
          [ discovered_url.path, match&.first ]
        end.compact
      end
    end
  end
end
