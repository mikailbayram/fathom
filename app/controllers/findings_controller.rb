class FindingsController < ApplicationController
  def show
    finding = Finding.includes(:claim, :scan, finding_sources: :chunk).find(params[:id])

    render inertia: "Findings/Show", props: {
      finding: FindingPresenter.new(finding).detail
    }
  end
end
