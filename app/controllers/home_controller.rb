class HomeController < ApplicationController
  FALLBACK_MESSAGE = "KC needs someone to talk right now.".freeze
  ESCALATION_PRIORITY_ORDER = {
    "low" => [ 0, 1, 2 ],
    "moderate" => [ 1, 2, 0],
    "high" => [ 2, 1, 0 ]
  }.freeze
  skip_forgery_protection only: :initiate_call

  def index; end

  def initiate_call
    activation_id = SecureRandom.uuid
    escalation_level = normalized_escalation_level(params[:escalation_level])
    intake = {
      feeling: params[:feeling].presence || "overwhelmed",
      trigger: params[:trigger].presence || "unspecified",
      urgency: params[:urgency].presence || "high"
    }
    user_id = params[:user_id].presence&.to_i || 1
    user = User.find(user_id)
    all_contacts = user.contacts.where(active: true, consent_status: :confirmed).to_a

    summary_payload = AgentServiceClient.new.start_activation(
      activation_id: activation_id,
      user_id: user_id,
      intake: intake,
      escalation_level: escalation_level,
      contacts: router_contacts_payload(all_contacts)
    )
    summary_text = summary_payload&.dig("summary_text").presence || FALLBACK_MESSAGE
    ordered_contacts = ordered_contacts_from_router(
      all_contacts: all_contacts,
      summary_payload: summary_payload,
      escalation_level: escalation_level
    )

    if ordered_contacts.empty?
      return respond_to do |format|
        format.html { redirect_to root_path, alert: "No active confirmed contacts for escalation #{escalation_level}." }
        format.json do
          render json: {
            status: "error",
            error: "no_contacts_for_escalation",
            activation_id: activation_id,
            escalation_level: escalation_level
          }, status: :unprocessable_entity
        end
      end
    end

    room_name = "activation_#{activation_id}"
    if local_base_url?(public_base_url)
      return respond_to do |format|
        format.html { redirect_to root_path, alert: "PUBLIC_BASE_URL must be a public https URL for Twilio callbacks." }
        format.json do
          render json: {
            status: "error",
            error: "invalid_public_base_url",
            message: "Twilio cannot reach localhost callbacks. Set PUBLIC_BASE_URL to your ngrok/public URL.",
            public_base_url: public_base_url
          }, status: :unprocessable_entity
        end
      end
    end

    session = CallSession.create!(
      room_name: room_name,
      caller_name: user.name.presence || "Someone",
      status: "calling"
    )
    session_contacts = build_session_contacts(session, ordered_contacts)

    call_results = call_contacts_in_batches(
      contacts: ordered_contacts,
      session_contacts: session_contacts,
      room_name: room_name,
      caller_name: user.name.presence || "Someone",
      escalation_level: escalation_level,
      base_url: public_base_url,
      summary_text: summary_text
    )
    session.refresh_status!
    call_sids = session.call_session_contacts.where.not(call_sid: nil).pluck(:call_sid)

    Rails.cache.write(
      activation_cache_key(activation_id),
      {
        "activation_id" => activation_id,
        "summary_text" => summary_text,
        "accepted_call_sid" => nil,
        "room_name" => room_name,
        "escalation_level" => escalation_level,
        "routed_contact_ids" => ordered_contacts.map(&:id),
        "call_sids" => call_sids,
        "created_at" => Time.current.iso8601
      },
      expires_in: 30.days
    )

    respond_to do |format|
      format.html { redirect_to root_path, notice: "Activation started. Calling #{ordered_contacts.size} contacts grouped by priority." }
      format.json do
        render json: {
          status: "ok",
          activation_id: activation_id,
          summary_text: summary_text,
          escalation_level: escalation_level,
          room_name: room_name,
          session_id: session.id,
          session_status: session.status,
          stream_url: "/api/calls/sessions/#{session.id}/stream",
          state_url: "/api/calls/sessions/#{session.id}",
          contacts: session.call_session_contacts.order(:id).map { |contact| contact_payload(contact) },
          routed_contact_ids: ordered_contacts.map(&:id),
          batches: call_results.map do |batch|
            {
              batch_number: batch[:batch_number],
              escalation_group: batch[:priority_label],
              contact_ids: batch[:contact_ids],
              contacts: batch[:results]
            }
          end
        }, status: :ok
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to root_path, alert: "User not found." }
      format.json { render json: { status: "error", error: "user_not_found", user_id: user_id }, status: :not_found }
    end
  rescue KeyError => e
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Missing environment variable: #{e.key}" }
      format.json { render json: { status: "error", error: "missing_env", key: e.key }, status: :unprocessable_entity }
    end
  rescue Twilio::REST::RestError => e
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Twilio error: #{e.message}" }
      format.json { render json: { status: "error", error: "twilio_error", message: e.message }, status: :bad_gateway }
    end
  end

  private

  def activation_cache_key(activation_id)
    "activation:#{activation_id}"
  end

  def normalized_escalation_level(raw_level)
    raw = raw_level.to_s.strip.downcase
    return raw if ESCALATION_PRIORITY_ORDER.key?(raw)

    case raw_level.to_i
    when 1 then "low"
    when 2 then "moderate"
    when 3 then "high"
    else "low"
    end
  end

  def router_contacts_payload(contacts)
    contacts.map do |contact|
      {
        id: contact.id,
        priority: contact_priority_value(contact),
        active: contact.active,
        preferred_hours_start: contact.preferred_hours_start&.strftime("%H:%M:%S"),
        preferred_hours_end: contact.preferred_hours_end&.strftime("%H:%M:%S"),
        timezone: contact.timezone,
        last_responded_at: contact.last_responded_at,
        response_count: contact.response_count,
        miss_count: contact.miss_count
      }
    end
  end

  def ordered_contacts_from_router(all_contacts:, summary_payload:, escalation_level:)
    ids = Array(summary_payload&.dig("routed_contacts")).map { |contact| contact["id"].to_i }.uniq
    contacts_by_id = all_contacts.index_by(&:id)
    ordered = ids.filter_map { |id| contacts_by_id[id] }
    return ordered if ordered.any?

    priority_order = ESCALATION_PRIORITY_ORDER.fetch(escalation_level)
    all_contacts
      .select { |contact| priority_order.include?(contact_priority_value(contact)) }
      .sort_by do |contact|
        reliability = reliability_score(contact)
        recency = contact.last_responded_at&.to_f || -Float::INFINITY
        priority_rank = priority_order.index(contact_priority_value(contact)) || priority_order.length
        [ priority_rank, -reliability, -recency, -contact.response_count, contact.id ]
      end
  end

  def reliability_score(contact)
    attempts = contact.response_count + contact.miss_count
    return 0.0 if attempts.zero?

    contact.response_count.fdiv(attempts)
  end

  def call_contacts_in_batches(
    contacts:,
    session_contacts:,
    room_name:,
    caller_name:,
    escalation_level:,
    base_url:,
    summary_text:
  )
    service = TwilioService.new
    ordered_groups = ESCALATION_PRIORITY_ORDER.fetch(escalation_level)
    priority_groups = contacts.group_by { |contact| contact_priority_value(contact) }
    session_contacts_by_phone = session_contacts.index_by(&:phone_number)
    requested_order = ordered_groups.select { |priority| priority_groups.key?(priority) }

    requested_order.each.with_index(1).map do |priority, batch_number|
      group_contacts = priority_groups.fetch(priority, [])
      tracked_contacts = group_contacts.filter_map { |contact| session_contacts_by_phone[contact.phone_e164] }
      results = service.call_everyone_with_tracking(
        session_contacts: tracked_contacts,
        room_name: room_name,
        caller_name: caller_name,
        base_url: base_url,
        summary_message: summary_text
      )

      {
        batch_number: batch_number,
        priority_label: priority_label(priority),
        contact_ids: group_contacts.map(&:id),
        results: results
      }
    end
  end

  def contact_priority_value(contact)
    return contact[:priority] if contact[:priority].is_a?(Integer)

    Contact.priorities.fetch(contact.priority.to_s)
  end

  def priority_label(priority_value)
    Contact.priorities.key(priority_value).to_s
  end

  def build_session_contacts(session, contacts)
    contacts.map do |contact|
      session.call_session_contacts.create!(
        phone_number: contact.phone_e164,
        status: "queued",
        last_event_at: Time.current
      )
    end
  end

  def public_base_url
    ENV["PUBLIC_BASE_URL"].to_s.strip.presence || request.base_url
  end

  def local_base_url?(url)
    host = URI.parse(url).host
    host.blank? || [ "localhost", "127.0.0.1", "::1" ].include?(host)
  rescue URI::InvalidURIError
    true
  end

  def contact_payload(contact)
    {
      id: contact.id,
      phone_number: contact.phone_number,
      call_sid: contact.call_sid,
      status: contact.status,
      error_message: contact.error_message,
      last_event_at: contact.last_event_at&.iso8601,
      updated_at: contact.updated_at&.iso8601
    }
  end
end
