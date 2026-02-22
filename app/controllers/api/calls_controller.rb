module Api
  class CallsController < ActionController::API
    include ActionController::Live

    E164_REGEX = /\A\+[1-9]\d{1,14}\z/
    STREAM_POLL_INTERVAL_SECONDS = 1
    STREAM_MAX_OPEN_SECONDS = 20
    STREAM_MAX_OPEN_SECONDS_DEVELOPMENT = 5

    # -----------------------------------------------------------------
    # POST /api/token
    # -----------------------------------------------------------------
    def token
      identity = params[:identity] || "user-#{SecureRandom.hex(4)}"

      service = ::TwilioService.new
      jwt = service.generate_access_token(identity: identity)

      render json: { token: jwt, identity: identity }, status: :ok
    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    end

    # -----------------------------------------------------------------
    # POST /api/call_everyone
    # Creates a tracked call session and places outbound calls.
    # -----------------------------------------------------------------
    def call_everyone
      room_name = params.require(:room_name).to_s.strip
      caller_name = params[:caller_name].to_s.strip.presence || "Someone"
      conference_name = params[:conference_name].to_s.strip
      conference_name = "alert-session-#{SecureRandom.hex(8)}" if conference_name.blank?
      abort_on_accept = boolean_param(params[:abort_on_accept], default: true)
      numbers = normalize_numbers(params.require(:numbers))

      if room_name.blank?
        return render json: { error: "room_name is required" }, status: :unprocessable_entity
      end

      if numbers.empty?
        return render json: { error: "numbers must contain valid E.164 values" }, status: :unprocessable_entity
      end

      session = CallSession.create!(
        room_name: room_name,
        caller_name: caller_name,
        conference_name: conference_name,
        auto_cancel_on_accept: abort_on_accept,
        status: "calling"
      )

      contacts = numbers.map do |number|
        session.call_session_contacts.create!(
          phone_number: number,
          status: "queued",
          last_event_at: Time.current
        )
      end

      service = ::TwilioService.new
      service.call_everyone_with_tracking(
        session_contacts: contacts,
        room_name: room_name,
        caller_name: caller_name,
        base_url: public_base_url
      )

      session.refresh_status!
      render json: session_payload(session.reload).merge(
        stream_url: "/api/calls/sessions/#{session.id}/stream",
        state_url: "/api/calls/sessions/#{session.id}"
      ), status: :created
    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    rescue ActiveRecord::NotNullViolation => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # -----------------------------------------------------------------
    # GET /api/calls/sessions/:id
    # -----------------------------------------------------------------
    def session_state
      session = CallSession.find(params[:id])
      render json: session_payload(session)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Session not found" }, status: :not_found
    end

    # -----------------------------------------------------------------
    # GET /api/calls/sessions/:id/stream
    # Server-Sent Events stream for live contact status changes.
    # -----------------------------------------------------------------
    def stream
      session = CallSession.find(params[:id])

      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"
      response.headers["Last-Modified"] = Time.current.httpdate

      stream = response.stream
      stream.write sse_event("snapshot", session_payload(session.reload))
      last_seen_at = session.updated_at || Time.current
      completed_since = nil
      stream_started_at = Time.current

      ActiveRecord::Base.connection_pool.with_connection do
        loop do
          break if (Time.current - stream_started_at) >= stream_max_open_seconds

          changed_contacts = session.call_session_contacts
                                    .where("updated_at > ?", last_seen_at)
                                    .order(updated_at: :asc, id: :asc)
                                    .to_a

          if changed_contacts.any?
            changed_contacts.each do |contact|
              stream.write sse_event("contact_update", contact_payload(contact))
            end

            session.reload
            stream.write sse_event("session_update", {
              session_id: session.id,
              status: session.status,
              updated_at: session.updated_at&.iso8601
            })

            last_seen_at = [ last_seen_at, session.updated_at, changed_contacts.last.updated_at ].compact.max
            completed_since = session.status == "completed" ? Time.current : nil
          else
            stream.write ": heartbeat\n\n"
            session.reload

            if session.status == "completed"
              completed_since ||= Time.current
              if Time.current - completed_since >= 3
                stream.write sse_event("session_end", {
                  session_id: session.id,
                  status: session.status
                })
                break
              end
            end
          end

          sleep STREAM_POLL_INTERVAL_SECONDS
        end
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Session not found" }, status: :not_found
    rescue ActionController::Live::ClientDisconnected, IOError
      # Expected when browser closes the stream.
    ensure
      begin
        response.stream.close
      rescue IOError
        nil
      end
    end

    # -----------------------------------------------------------------
    # POST /api/calls/status_callback
    # Twilio call lifecycle callback.
    # -----------------------------------------------------------------
    def status_callback
      contact = find_contact_from_callback
      return head :ok unless contact

      updates = {}
      call_sid = params[:CallSid].to_s.strip
      mapped_status = map_twilio_status(
        call_status: params[:CallStatus].to_s.strip,
        current_status: contact.status
      )

      updates[:call_sid] = call_sid if call_sid.present? && contact.call_sid.blank?
      updates[:status] = mapped_status if mapped_status.present? && mapped_status != contact.status

      if mapped_status == "failed"
        error_message = [ params[:ErrorCode], params[:ErrorMessage] ].compact.join(": ").presence
        updates[:error_message] = error_message if error_message.present?
      end

      if updates.any?
        updates[:last_event_at] = Time.current
        contact.update!(updates)
        contact.call_session.refresh_status!
      end

      head :ok
    rescue StandardError => e
      Rails.logger.error("[CallsController] status_callback error: #{e.class}: #{e.message}")
      head :ok
    end

    # -----------------------------------------------------------------
    # POST /api/calls/gather_response
    # Twilio gather callback for keypad input.
    # -----------------------------------------------------------------
    def gather_response
      contact = find_contact_from_callback
      return render xml: invalid_callback_twiml, content_type: "text/xml" unless contact

      digits = params[:Digits].to_s.strip
      session = contact.call_session
      call_sid = params[:CallSid].to_s.strip
      should_cancel_others = false
      call_sids_to_hangup = []
      summary_message = nil

      twiml = nil

      session.with_lock do
        session.reload
        contact.reload

        updates = { last_event_at: Time.current }
        updates[:call_sid] = call_sid if call_sid.present? && contact.call_sid.blank?

        if digits == "1"
          winner_id = session.connected_contact_id

          if winner_id.present? && winner_id != contact.id
            updates[:status] = "canceled" unless CallSessionContact::FINAL_STATUSES.include?(contact.status)
            contact.update!(updates) if updates.any?
            twiml = already_accepted_twiml
          else
            updates[:status] = "joined"
            contact.update!(updates)

            if winner_id.blank?
              session.update!(connected_contact_id: contact.id)
              if session.auto_cancel_on_accept?
                should_cancel_others = true
                call_sids_to_hangup = mark_other_contacts_canceled!(session:, winner_contact: contact)
              end
            end

            summary_message = summary_message_for_contact(contact)
            twiml = accepted_twiml(summary_message:)
          end
        else
          updates[:status] = "declined"
          contact.update!(updates)
          twiml = decline_twiml
        end

        session.refresh_status!
      end

      hangup_other_calls(call_sids_to_hangup) if should_cancel_others && call_sids_to_hangup.any?

      render xml: twiml, content_type: "text/xml"
    rescue StandardError => e
      Rails.logger.error("[CallsController] gather_response error: #{e.class}: #{e.message}")
      render xml: invalid_callback_twiml, content_type: "text/xml"
    end

    # -----------------------------------------------------------------
    # POST /api/hangup_calls
    # -----------------------------------------------------------------
    def hangup_calls
      call_sids = params.require(:call_sids)

      unless call_sids.is_a?(Array) && call_sids.any?
        return render json: { error: "call_sids must be a non-empty array" }, status: :unprocessable_entity
      end

      service = ::TwilioService.new
      results = service.hangup_calls(call_sids: call_sids)

      render json: { results: results }, status: :ok
    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # -----------------------------------------------------------------
    # POST /api/send_sms
    # -----------------------------------------------------------------
    def send_sms
      number = params.require(:number)
      message = params.require(:message)

      service = ::TwilioService.new
      result = service.send_sms(to: number, message: message)

      render json: { sid: result.sid, status: result.status, to: result.to }, status: :ok
    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue Twilio::REST::RestError => e
      render json: { error: "Twilio error: #{e.message}" }, status: :unprocessable_entity
    end

    # -----------------------------------------------------------------
    # POST /api/send_sms_all
    # -----------------------------------------------------------------
    def send_sms_all
      numbers = params.require(:numbers)
      message = params.require(:message)

      unless numbers.is_a?(Array) && numbers.any?
        return render json: { error: "numbers must be a non-empty array" }, status: :unprocessable_entity
      end

      service = ::TwilioService.new
      results = service.send_sms_all(numbers: numbers, message: message)

      render json: { results: results }, status: :ok
    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def public_base_url
      ENV["PUBLIC_BASE_URL"].to_s.strip.presence || request.base_url
    end

    def normalize_numbers(raw_numbers)
      return [] unless raw_numbers.is_a?(Array)

      raw_numbers
        .map { |number| normalize_number(number) }
        .compact
        .uniq
    end

    def normalize_number(number)
      cleaned = number.to_s.strip.gsub(/[^\d+]/, "")
      return nil if cleaned.blank?

      normalized = cleaned.start_with?("+") ? cleaned : "+#{cleaned}"
      normalized.match?(E164_REGEX) ? normalized : nil
    end

    def find_contact_from_callback
      contact_id = params[:contact_id] || params[:ContactId]
      return nil if contact_id.blank?

      CallSessionContact.find_by(id: contact_id)
    end

    def map_twilio_status(call_status:, current_status:)
      if CallSessionContact::FINAL_STATUSES.include?(current_status) && current_status != "joined"
        return current_status
      end

      case call_status
      when "queued", "initiated"
        "calling"
      when "ringing"
        "ringing"
      when "in-progress"
        current_status == "joined" ? "joined" : "picked_up"
      when "completed"
        return "declined" if %w[calling ringing picked_up].include?(current_status)
        CallSessionContact::FINAL_STATUSES.include?(current_status) ? current_status : "completed"
      when "busy"
        "declined"
      when "failed"
        "failed"
      when "no-answer"
        "no_answer"
      when "canceled"
        "canceled"
      else
        nil
      end
    end

    def accepted_twiml(summary_message: nil)
      spoken_summary = normalized_summary_message(summary_message)

      Twilio::TwiML::VoiceResponse.new do |r|
        r.say(voice: "alice", message: "Thanks. You are marked as accepted.")
        if spoken_summary.present?
          r.pause(length: 5)
          r.say(voice: "alice", message: spoken_summary)
          r.say(voice: "alice", message: "Please stay on the line.")
          r.pause(length: 600)
        else
          r.say(voice: "alice", message: "Goodbye.")
          r.hangup
        end
      end.to_s
    end

    def decline_twiml
      Twilio::TwiML::VoiceResponse.new do |r|
        r.say(voice: "alice", message: "Thanks for letting us know.")
        r.say(voice: "alice", message: "Goodbye.")
        r.hangup
      end.to_s
    end

    def already_accepted_twiml
      Twilio::TwiML::VoiceResponse.new do |r|
        r.say(voice: "alice", message: "Someone has already accepted this request. Thank you.")
        r.say(voice: "alice", message: "Goodbye.")
        r.hangup
      end.to_s
    end

    def invalid_callback_twiml
      Twilio::TwiML::VoiceResponse.new do |r|
        r.say(voice: "alice", message: "This link is no longer valid. Goodbye.")
        r.hangup
      end.to_s
    end

    def session_payload(session)
      {
        session_id: session.id,
        room_name: session.room_name,
        caller_name: session.caller_name,
        auto_cancel_on_accept: session.auto_cancel_on_accept,
        status: session.status,
        contacts: session.call_session_contacts.order(:id).map { |contact| contact_payload(contact) },
        created_at: session.created_at&.iso8601,
        updated_at: session.updated_at&.iso8601
      }
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

    def sse_event(name, payload)
      +"event: #{name}\ndata: #{payload.to_json}\n\n"
    end

    def summary_message_for_contact(contact)
      room_name = contact.call_session&.room_name.to_s
      activation_id = room_name.delete_prefix("activation_")
      return nil if activation_id.blank? || activation_id == room_name

      Rails.cache.read("activation:#{activation_id}")&.dig("summary_text")
    rescue StandardError
      nil
    end

    def normalized_summary_message(message)
      text = message.to_s.strip
      return nil if text.blank?

      text.tr("\n", " ")[0, 500]
    end

    def boolean_param(raw_value, default:)
      return true if [true, 1, "1", "true", "on", "yes"].include?(raw_value)
      return false if [false, 0, "0", "false", "off", "no"].include?(raw_value)

      default
    end

    def mark_other_contacts_canceled!(session:, winner_contact:)
      contacts_to_cancel = session.call_session_contacts
                                 .where.not(id: winner_contact.id)
                                 .where.not(status: CallSessionContact::FINAL_STATUSES)
                                 .to_a

      now = Time.current
      contacts_to_cancel.each do |other_contact|
        other_contact.update!(
          status: "canceled",
          last_event_at: now
        )
      end

      contacts_to_cancel.filter_map(&:call_sid).uniq
    end

    def hangup_other_calls(call_sids)
      return if call_sids.blank?

      TwilioService.new.hangup_calls(call_sids: call_sids)
    rescue StandardError => e
      Rails.logger.warn("[CallsController] Could not hang up competing calls: #{e.class}: #{e.message}")
    end

    def stream_max_open_seconds
      Rails.env.development? ? STREAM_MAX_OPEN_SECONDS_DEVELOPMENT : STREAM_MAX_OPEN_SECONDS
    end
  end
end
