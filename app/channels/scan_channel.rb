# Streams scan progress to the pages that display it.
#
# Polling still runs underneath this, and deliberately: the counters inside a
# stage -- pages crawled, passages indexed -- tick continuously and are not
# worth a broadcast each. What the socket carries is the thing a poll made look
# stuck: the moment a scan changes stage, fails, or finishes.
#
# Two subscriptions, because the two pages need different things. One lead's
# page wants that lead's whole status payload. The list wants to know only that
# something moved, and reloads its own props rather than having a second copy of
# the row shape live here.
class ScanChannel < ApplicationCable::Channel
  LIST_STREAM = "leads:list"

  def subscribed
    # Everything this streams is internal: which companies are being scanned,
    # how far along, and what it cost. A demo visitor has a valid connection and
    # no business here.
    return reject unless operator

    return stream_from(LIST_STREAM) if params[:lead_id].blank?

    lead = Lead.find_by(id: params[:lead_id])
    return reject if lead.nil?

    stream_for lead
  end

  # A deleted scan has no status to send, but the list still has a row to
  # redraw.
  def self.broadcast_removed(lead)
    ActionCable.server.broadcast(LIST_STREAM, { lead_id: lead.id, status: nil })
  end

  def self.broadcast_status(scan)
    broadcast_to(scan.lead, LeadPresenter.new(scan.lead).status)
    ActionCable.server.broadcast(LIST_STREAM, { lead_id: scan.lead_id, status: scan.status })
  end
end
