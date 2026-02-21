module Api
  class CallsController < ActionController::API
    # -----------------------------------------------------------------
    # POST /api/token
    #
    # Returns a Twilio Access Token so the browser can connect to
    # Twilio Voice via WebRTC.
    #
    # Params:
    #   identity – a unique string identifying this browser user
    # -----------------------------------------------------------------
    def token
      identity = params[:identity] || "user-#{SecureRandom.hex(4)}"

      service = TwilioService.new
      jwt = service.generate_access_token(identity: identity)

      render json: { token: jwt, identity: identity }, status: :ok

    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    end

    # -----------------------------------------------------------------
    # POST /api/call_everyone
    #
    # Calls a list of numbers simultaneously. Each contact hears a
    # message and can press 1 to join the caller's conference room.
    #
    # Params:
    #   numbers[]   – array of E.164 phone numbers to call
    #   room_name   – the conference room the browser caller joined
    #   caller_name – optional human-readable name
    # -----------------------------------------------------------------
    def call_everyone
      numbers     = params.require(:numbers)
      room_name   = params.require(:room_name)
      caller_name = params[:caller_name] || "Someone"

      unless numbers.is_a?(Array) && numbers.any?
        return render json: { error: "numbers must be a non-empty array" }, status: :unprocessable_entity
      end

      service = TwilioService.new
      session = service.call_everyone(
        numbers: numbers,
        room_name: room_name,
        caller_name: caller_name
      )

      render json: {
        session_id: session.id,
        status: session.status,
        contacts: session.session_contacts.map { |c|
          { phone_number: c.phone_number, call_sid: c.call_sid, status: c.status }
        }
      }, status: :created

    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # -----------------------------------------------------------------
    # POST /api/hangup_others
    #
    # After someone connects, hang up the remaining ringing calls.
    # Optionally exclude a specific number (the one who connected).
    #
    # Params:
    #   session_id     – the session to act on
    #   except_number  – (optional) E.164 number to keep connected
    # -----------------------------------------------------------------
    def hangup_others
      session = Session.find(params.require(:session_id))
      except  = params[:except_number]

      service = TwilioService.new
      service.hangup_others(session, except_number: except)

      session.update!(status: "connected")

      render json: { session_id: session.id, status: "connected" }, status: :ok

    rescue ActiveRecord::RecordNotFound
      render json: { error: "Session not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # -----------------------------------------------------------------
    # POST /api/send_sms
    #
    # Send an SMS to a single number.
    #
    # Params:
    #   number  – E.164 phone number
    #   message – text body
    # -----------------------------------------------------------------
    def send_sms
      number  = params.require(:number)
      message = params.require(:message)

      service = TwilioService.new
      result  = service.send_sms(to: number, message: message)

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
    #
    # Send an SMS to multiple numbers.
    #
    # Params:
    #   numbers[] – array of E.164 phone numbers
    #   message   – text body
    # -----------------------------------------------------------------
    def send_sms_all
      numbers = params.require(:numbers)
      message = params.require(:message)

      unless numbers.is_a?(Array) && numbers.any?
        return render json: { error: "numbers must be a non-empty array" }, status: :unprocessable_entity
      end

      service = TwilioService.new
      results = service.send_sms_all(numbers: numbers, message: message)

      render json: { results: results }, status: :ok

    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
