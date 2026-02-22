class StudioController < ApplicationController
  def index
    @contacts = [
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
  end
end
