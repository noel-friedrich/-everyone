class AlertsController < ApplicationController
  def index
    user_id = params[:user_id].presence&.to_i || 1
    confirmed_contacts = Contact.where(
      user_id: user_id,
      active: true,
      consent_status: Contact.consent_statuses.fetch("confirmed")
    ).order(:id)

    @callable_contact_count = confirmed_contacts.count
    @db_confirmed_contacts = confirmed_contacts.map do |contact|
      {
        name: contact.name,
        phone: contact.phone_e164
      }
    end
  rescue StandardError
    @callable_contact_count = 0
    @db_confirmed_contacts = []
  end
end
