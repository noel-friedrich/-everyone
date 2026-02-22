import { Controller } from "@hotwired/stimulus";
import { ensureClientUid } from "client_uid";

const CONSENT_STATUSES = ["pending", "confirmed", "declined"];
const E164_REGEX = /^\+[1-9]\d{1,14}$/;

function normalizeStatus(rawStatus) {
  if (CONSENT_STATUSES.includes(rawStatus)) return rawStatus;
  if (rawStatus === "revoked") return "declined";
  return "pending";
}

function normalizePhone(rawPhone) {
  const digitsAndPlus = String(rawPhone || "")
    .trim()
    .replace(/[^\d+]/g, "");
  if (!digitsAndPlus) return "";

  const withoutLeadingPluses = digitsAndPlus.replace(/^\++/, "");
  if (!withoutLeadingPluses) return "";

  const candidate = `+${withoutLeadingPluses}`;
  return E164_REGEX.test(candidate) ? candidate : "";
}

function sanitizeContact(raw) {
  return {
    name: String(raw?.name || "").trim(),
    phone: normalizePhone(raw?.phone),
    status: normalizeStatus(raw?.status),
  };
}

function isUsableContact(contact) {
  return Boolean(contact?.name) && Boolean(contact?.phone);
}

function mergeContactsByPhone(...contactLists) {
  const merged = new Map();

  contactLists.flat().forEach((rawContact) => {
    const contact = sanitizeContact(rawContact);
    if (!isUsableContact(contact)) return;

    const existing = merged.get(contact.phone) || {};
    merged.set(contact.phone, { ...existing, ...contact });
  });

  return Array.from(merged.values());
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

async function sha256Hex(input) {
  const encoded = new TextEncoder().encode(input);
  const digest = await window.crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export default class extends Controller {
  static targets = [
    "tbody",
    "editor",
    "editorTitle",
    "nameInput",
    "phoneInput",
  ];

  static values = {
    initial: Array,
    storageKey: String,
  };

  connect() {
    this.editingIndex = null;
    this.clientUid = ensureClientUid();
    this.contacts = this.loadContacts();
    this.renderRows();
    this.syncStatusesFromServer();
    this.syncTimer = window.setInterval(
      () => this.syncStatusesFromServer(),
      15000,
    );
  }

  disconnect() {
    if (this.syncTimer) {
      window.clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
  }

  startAdd() {
    this.editingIndex = null;
    this.editorTitleTarget.textContent = "Add contact";
    this.nameInputTarget.value = "";
    this.phoneInputTarget.value = "";
    this.editorTarget.hidden = false;
    this.nameInputTarget.focus();
  }

  edit(event) {
    const index = Number(event.currentTarget.dataset.index);
    const contact = this.contacts[index];
    if (!contact) return;

    this.editingIndex = index;
    this.editorTitleTarget.textContent = "Edit contact";
    this.nameInputTarget.value = contact.name;
    this.phoneInputTarget.value = contact.phone;
    this.editorTarget.hidden = false;
    this.nameInputTarget.focus();
  }

  remove(event) {
    const index = Number(event.currentTarget.dataset.index);
    if (Number.isNaN(index)) return;
    this.contacts.splice(index, 1);
    this.persist();
    this.renderRows();
  }

  async save(event) {
    event.preventDefault();

    const previousContact =
      this.editingIndex === null ? null : this.contacts[this.editingIndex];
    const normalizedPhone = normalizePhone(this.phoneInputTarget.value);
    const draft = sanitizeContact({
      name: this.nameInputTarget.value,
      phone: normalizedPhone,
      status:
        this.editingIndex === null
          ? "pending"
          : this.contacts[this.editingIndex]?.status || "pending",
    });

    if (!draft.name || !draft.phone) return;

    if (this.editingIndex === null) {
      this.contacts.push(draft);
    } else {
      this.contacts[this.editingIndex] = draft;
    }

    const needsNewConsent =
      this.editingIndex === null || previousContact?.phone !== draft.phone;

    this.persist();
    this.renderRows();
    this.cancel();

    try {
      const consentHash = await this.hashForPhone(draft.phone);
      if (needsNewConsent) {
        const existing = await this.bulkLookup([consentHash]);
        const existingStatus = normalizeStatus(existing[consentHash]);
        if (existingStatus !== "declined") {
          await this.sendOptInSms({
            hash: consentHash,
            number: draft.phone,
            name: draft.name,
          });
        }
      }
      await this.syncStatusesFromServer();
    } catch (error) {
      console.error("Failed to save consent hash", error);
    }
  }

  cancel() {
    this.editorTarget.hidden = true;
    this.editingIndex = null;
  }

  loadContacts() {
    const storageKey = this.storageKeyValue || "studio_contacts_v1";
    const raw = localStorage.getItem(storageKey);
    const initialContacts = Array.isArray(this.initialValue) ? this.initialValue : [];

    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
          const merged = mergeContactsByPhone(parsed, initialContacts);
          localStorage.setItem(storageKey, JSON.stringify(merged));
          return merged;
        }
      } catch (_) {
        // If malformed, fall back to initial sample data below.
      }
    }

    const fallback = mergeContactsByPhone(initialContacts);
    localStorage.setItem(storageKey, JSON.stringify(fallback));
    return fallback;
  }

  persist() {
    const storageKey = this.storageKeyValue || "studio_contacts_v1";
    localStorage.setItem(storageKey, JSON.stringify(this.contacts));
  }

  async hashForPhone(phone) {
    const normalized = normalizePhone(phone);
    if (!normalized) throw new Error("Invalid phone number for hashing");
    return sha256Hex(`${this.clientUid}${normalized}`);
  }

  async syncStatusesFromServer() {
    if (this.contacts.length === 0) return;

    try {
      const consentHashes = await Promise.all(
        this.contacts.map((contact) => this.hashForPhone(contact.phone)),
      );
      const knownStatuses = await this.bulkLookup(consentHashes);

      let changed = false;
      this.contacts = this.contacts.map((contact, index) => {
        const lookupStatus = knownStatuses[consentHashes[index]];
        const status =
          lookupStatus === undefined
            ? contact.status
            : normalizeStatus(lookupStatus);
        if (contact.status !== status) changed = true;
        return { ...contact, status };
      });

      if (changed) this.persist();
      this.renderRows();
    } catch (error) {
      console.error("Failed to sync consent statuses", error);
    }
  }

  async bulkLookup(hashes) {
    const response = await fetch("/api/helper_consents/bulk_lookup", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ hashes }),
    });

    if (!response.ok) {
      throw new Error(`bulk_lookup failed with status ${response.status}`);
    }

    const payload = await response.json();
    return payload.consents || {};
  }

  async sendOptInSms({ hash, number, name }) {
    const response = await fetch("/api/helper_consents/send_opt_in", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ hash, number, name }),
    });

    if (!response.ok) {
      throw new Error(`send_opt_in failed with status ${response.status}`);
    }
  }

  renderRows() {
    if (this.contacts.length === 0) {
      this.tbodyTarget.innerHTML = `
        <tr>
          <td colspan="4" class="studio-empty">No contacts yet. Add your first contact.</td>
        </tr>
      `;
      return;
    }

    this.tbodyTarget.innerHTML = this.contacts
      .map((contact, index) => {
        const statusClass =
          contact.status === "confirmed"
            ? "is-confirmed"
            : contact.status === "declined"
              ? "is-declined"
              : "is-pending";
        const statusLabel =
          contact.status === "confirmed"
            ? "Confirmed"
            : contact.status === "declined"
              ? "Declined"
              : "Pending";
        return `
          <tr>
            <td>${escapeHtml(contact.name)}</td>
            <td>${escapeHtml(contact.phone)}</td>
            <td>
              <span class="studio-status ${statusClass}">${statusLabel}</span>
            </td>
            <td>
              <div class="studio-actions">
                <button type="button" class="studio-action-btn" data-index="${index}" data-action="click->studio-contacts#edit">Edit</button>
                <button type="button" class="studio-action-btn is-danger" data-index="${index}" data-action="click->studio-contacts#remove">Remove</button>
              </div>
            </td>
          </tr>
        `;
      })
      .join("");
  }
}
