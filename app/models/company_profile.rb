# What the analysis model understood about the company, from its own content.
class CompanyProfile < ApplicationRecord
  belongs_to :scan

  validates :company_name, presence: true

  def named_integrations = Array(integrations)
  def concerns = Array(enterprise_concerns)
end
