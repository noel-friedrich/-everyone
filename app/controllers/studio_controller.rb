class StudioController < ApplicationController
  def index
    @contacts = [
      {
        name: "Sofia Reed",
        phone: "+49 176 1000 1234",
        confirmed: true
      },
      {
        name: "Daniel Park",
        phone: "+49 176 1000 8891",
        confirmed: false
      },
      {
        name: "Maya Klein",
        phone: "+49 176 1000 5520",
        confirmed: true
      },
      {
        name: "Elias Novak",
        phone: "+49 176 1000 4408",
        confirmed: false
      },
      {
        name: "Lea Schmidt",
        phone: "+49 176 1000 3372",
        confirmed: true
      },
      {
        name: "Jonas Weber",
        phone: "+49 176 1000 9914",
        confirmed: true
      },
      {
        name: "Nina Duarte",
        phone: "+49 176 1000 2816",
        confirmed: false
      },
      {
        name: "Theo Martens",
        phone: "+49 176 1000 6423",
        confirmed: true
      },
      {
        name: "Alina Costa",
        phone: "+49 176 1000 7158",
        confirmed: false
      },
      {
        name: "Marek Hoffmann",
        phone: "+49 176 1000 5067",
        confirmed: false
      }
    ]
  end
end
