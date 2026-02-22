import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["panel", "button"];

  connect() {
    this.expanded = false;
    this.applyState();
  }

  toggle() {
    this.expanded = !this.expanded;
    this.applyState();
  }

  applyState() {
    if (!this.hasPanelTarget || !this.hasButtonTarget) return;

    this.panelTarget.classList.toggle("is-open", this.expanded);
    this.panelTarget.setAttribute("aria-hidden", String(!this.expanded));
    this.buttonTarget.setAttribute("aria-expanded", String(this.expanded));
    this.buttonTarget.textContent = this.expanded
      ? "Hide setup form"
      : "Set up your circle";

    if (this.expanded) {
      window.requestAnimationFrame(() => {
        this.panelTarget.scrollIntoView({
          behavior: "smooth",
          block: "start",
          inline: "nearest",
        });
      });
    }
  }
}
