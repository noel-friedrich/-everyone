module Api
  class CallsController < ActionController::API
    # -----------------------------------------------------------------
    # POST /api/token
    #
    # Returns a Twilio Access Token so the browser can connect to
    # Twilio Voice via WebRTC.
    #
    # Params:
    #   identity – (optional) a unique string identifying this browser user
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
    #   caller_name – (optional) human-readable name
    #
    # Returns:
    #   { contacts: [{ number, call_sid, status }, ...] }
    # -----------------------------------------------------------------
    def call_everyone
      numbers     = params.require(:numbers)
      room_name   = params.require(:room_name)
      caller_name = params[:caller_name] || "Someone"

      unless numbers.is_a?(Array) && numbers.any?
        return render json: { error: "numbers must be a non-empty array" }, status: :unprocessable_entity
      end

      service = TwilioService.new
      results = service.call_everyone(
        numbers: numbers,
        room_name: room_name,
        caller_name: caller_name
      )

      render json: { contacts: results }, status: :created

    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # -----------------------------------------------------------------
    # POST /api/hangup_calls
    #
    # Hang up a list of active calls by their Twilio Call SIDs.
    # Use this after someone connects to stop the other phones ringing.
    #
    # Params:
    #   call_sids[] – array of Twilio Call SIDs to terminate
    # -----------------------------------------------------------------
    def hangup_calls
      call_sids = params.require(:call_sids)

      unless call_sids.is_a?(Array) && call_sids.any?
        return render json: { error: "call_sids must be a non-empty array" }, status: :unprocessable_entity
      end

      service = TwilioService.new
      results = service.hangup_calls(call_sids: call_sids)

      render json: { results: results }, status: :ok

    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
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
