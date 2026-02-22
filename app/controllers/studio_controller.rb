class StudioController < ApplicationController
  def index
    sample_contacts = [
      {
        name: "Sofia Reed",
        phone: "+49 176 1000 1234"
      },
      {
        name: "Daniel Park",
        phone: "+49 176 1000 8891"
      },
      {
        name: "Maya Klein",
        phone: "+49 176 1000 5520"
      },
      {
        name: "Elias Novak",
        phone: "+49 176 1000 4408"
      },
      {
        name: "Lea Schmidt",
        phone: "+49 176 1000 3372"
      },
      {
        name: "Jonas Weber",
        phone: "+49 176 1000 9914"
      },
      {
        name: "Nina Duarte",
        phone: "+49 176 1000 2816"
      },
      {
        name: "Theo Martens",
        phone: "+49 176 1000 6423"
      },
      {
        name: "Alina Costa",
        phone: "+49 176 1000 7158"
      },
      {
        name: "Marek Hoffmann",
        phone: "+49 176 1000 5067"
      }
    ]

    db_confirmed_contacts = Contact
      .where(user_id: 1, active: true, consent_status: Contact.consent_statuses.fetch("confirmed"))
      .order(:id)
      .map do |contact|
        {
          name: contact.name,
          phone: contact.phone_e164,
          status: "confirmed"
        }
      end

    @contacts = merge_contacts_by_phone(sample_contacts, db_confirmed_contacts)
  rescue StandardError
    @contacts = sample_contacts || []
  end

  private

  def merge_contacts_by_phone(*contact_lists)
    merged = {}

    contact_lists.flatten.compact.each do |contact|
      phone = contact[:phone].to_s.gsub(/[^\d+]/, "")
      next if phone.blank?

      normalized_phone = phone.start_with?("+") ? phone : "+#{phone}"
      existing = merged[normalized_phone] || {}
      merged[normalized_phone] = existing.merge(contact).merge(phone: normalized_phone)
    end

    merged.values
  end
end
