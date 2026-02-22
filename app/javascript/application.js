// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";
import { ensureClientUid } from "client_uid";

document.addEventListener("turbo:load", () => {
  ensureClientUid();
});
