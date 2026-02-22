Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
  get "studio" => "studio#index", as: :studio
  get "alert" => "alerts#index", as: :alert
  get "consent" => "consents#show", as: :consent
  post "consent/respond" => "consents#respond", as: :consent_respond
  post "initiate_call" => "home#initiate_call", as: :initiate_call
  post "initiate_all" => "home#initiate_call", as: :initiate_all

  post "twilio/voice/intro" => "twilio_voice#intro", as: :twilio_voice_intro
  post "twilio/voice/accept" => "twilio_voice#accept", as: :twilio_voice_accept
  post "twilio/voice/status" => "twilio_voice#status", as: :twilio_voice_status
  namespace :api do
    post "token" => "calls#token"
    post "call_everyone" => "calls#call_everyone"
    post "hangup_calls" => "calls#hangup_calls"
    post "send_sms" => "calls#send_sms"
    post "send_sms_all" => "calls#send_sms_all"
    get "calls/sessions/:id" => "calls#session_state"
    get "calls/sessions/:id/stream" => "calls#stream"
    post "calls/status_callback" => "calls#status_callback"
    post "calls/gather_response" => "calls#gather_response"
    post "helper_consents" => "helper_consents#upsert"
    post "helper_consents/bulk_lookup" => "helper_consents#bulk_lookup"
    post "helper_consents/send_opt_in" => "helper_consents#send_opt_in"
  end
end
