# A salesperson answering a question their own website could not.
class HandoffsController < ApplicationController
  def update
    handoff = Handoff.find(params[:id])

    if params[:dismiss].present?
      handoff.dismissed!
    else
      answer = params[:answer].to_s.strip
      return redirect_back_or_to(root_path) if answer.blank?

      handoff.answer!(answer)
    end

    redirect_to lead_path(handoff.scan.lead, tab: "questions")
  end
end
