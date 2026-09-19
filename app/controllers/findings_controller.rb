class FindingsController < ApplicationController
  def show
    finding = Finding.includes(:claim, { scan: :lead }, finding_sources: { chunk: :page }).find(params[:id])

    render inertia: "Findings/Show", props: {
      finding: FindingPresenter.new(finding).detail
    }
  end
end
