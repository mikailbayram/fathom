# A company/domain a salesperson wants to understand. One lead, many scans.
class Lead < ApplicationRecord
  has_many :scans, -> { order(created_at: :desc) }, dependent: :destroy, inverse_of: :lead

  validates :name, presence: true
  validates :domain, presence: true, uniqueness: true
  validates :website_url, presence: true

  # Accepts anything a salesperson is likely to paste -- "acme.com",
  # "https://www.acme.com/pricing?utm_source=x" -- and resolves it to the one
  # lead record for that registrable domain.
  def self.for_website(input)
    site = Url.site(input)
    raise Url::Invalid, "Enter a valid website address" if site.nil?

    find_or_create_by!(domain: site.domain) do |lead|
      lead.website_url = site.website_url
      lead.name = site.name
    end
  end

  def latest_scan = scans.first
end
