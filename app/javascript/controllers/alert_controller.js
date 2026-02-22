import { Controller } from "@hotwired/stimulus";
import { ensureClientUid } from "client_uid";

const CONTACT_STORAGE_KEY = "studio_contacts_v1";
const E164_REGEX = /^\+[1-9]\d{1,14}$/;
const FINAL_CALL_STATUSES = new Set([
  "joined",
  "declined",
  "no_answer",
  "busy",
  "failed",
  "canceled",
  "completed",
]);
const ACTIVE_CALL_STATUSES = new Set([
  "queued",
  "calling",
  "ringing",
  "picked_up",
]);
const OPEN_CALL_STATUSES = new Set(["ready", ...ACTIVE_CALL_STATUSES]);
const NO_RESPONSE_STATUSES = new Set([
  "no_answer",
  "busy",
  "failed",
  "canceled",
  "completed",
]);
const PERSON_ICON_SVG =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="7.5" r="3.6"></circle><path d="M4.5 19c1.6-3.4 4.1-5 7.5-5s5.9 1.6 7.5 5"></path></svg>';
const DEMO_FALLBACK_CONTACTS = [
  { name: "Alex", phone: "+10000000001" },
  { name: "Sam", phone: "+10000000002" },
  { name: "Noor", phone: "+10000000003" },
  { name: "Jules", phone: "+10000000004" },
  { name: "Mika", phone: "+10000000005" },
  { name: "Taylor", phone: "+10000000006" },
  { name: "Rin", phone: "+10000000007" },
  { name: "Casey", phone: "+10000000008" },
  { name: "Jordan", phone: "+10000000009" },
  { name: "Parker", phone: "+10000000010" },
];
const ALERT_PROMPT_STEPS = [
  {
    key: "feeling",
    title: "How are you feeling right now?",
    hint: "Choose the option that best fits right now.",
    options: [
      "overwhelmed",
      "anxious",
      "panicked",
      "sad",
      "angry",
      "numb",
      "confused",
      "unsafe",
    ],
  },
  {
    key: "trigger",
    title: "What caused your distress?",
    hint: "Pick the closest cause so the summary has context.",
    options: [
      "panic_attack",
      "conflict",
      "work_stress",
      "family_issue",
      "relationship_issue",
      "health_scare",
      "loneliness",
      "other",
    ],
  },
  {
    key: "urgency",
    title: "How urgent is your request?",
    hint: "This affects who gets called first.",
    options: ["low", "moderate", "high"],
  },
];

function stageBucketForStatus(status) {
  if (status === "ready") return null;
  if (status === "joined") return "accepted";
  if (status === "declined") return "declined";
  if (NO_RESPONSE_STATUSES.has(status)) return "no_response";
  return "calling";
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

function sanitizeLocalContact(raw) {
  return {
    name: String(raw?.name || "").trim(),
    phone: normalizePhone(raw?.phone),
  };
}

function mergeAlertContactsByPhone(...contactLists) {
  const merged = new Map();

  contactLists.flat().forEach((rawContact) => {
    const contact = sanitizeLocalContact(rawContact);
    if (!contact.name || !contact.phone) return;

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

function callStatusLabel(status) {
  switch (status) {
    case "queued":
    case "calling":
    case "ringing":
      return "Calling";
    case "picked_up":
      return "Picked up";
    case "joined":
      return "Accepted";
    case "declined":
      return "Declined";
    case "no_answer":
      return "No answer";
    case "busy":
      return "Busy";
    case "failed":
      return "Failed";
    case "canceled":
      return "Canceled";
    case "completed":
      return "Hung up";
    default:
      return "Ready";
  }
}

function statusClass(status) {
  if (status === "joined") return "is-confirmed";
  if (ACTIVE_CALL_STATUSES.has(status) || status === "ready")
    return "is-pending";
  return "is-declined";
}

function statusSortRank(status) {
  if (status === "joined") return 0;
  if (ACTIVE_CALL_STATUSES.has(status) || status === "ready") return 1;
  if (status === "declined") return 2;
  if (NO_RESPONSE_STATUSES.has(status)) return 3;
  return 4;
}

export default class extends Controller {
  static targets = [
    "tbody",
    "alertButton",
    "cancelButton",
    "error",
    "intakeCard",
    "intakeProgress",
    "intakeTitle",
    "intakeHint",
    "intakeOptions",
    "stage",
    "iconLayer",
    "callingZone",
    "declinedZone",
    "noResponseZone",
    "acceptedZone",
    "callingCount",
    "declinedCount",
    "noResponseCount",
    "acceptedCount",
  ];

  connect() {
    this.clientUid = ensureClientUid();
    this.pageParams = new URLSearchParams(window.location.search);
    this.demoMode = new URLSearchParams(window.location.search).has("demo");
    this.dbContactCount = Number(this.alertButtonTarget.dataset.dbCount) || 0;
    this.autoStartRequested = false;
    this.autoStartAttempted = false;
    this.promptSteps = ALERT_PROMPT_STEPS;
    this.promptStepIndex = 0;
    this.promptCompleted = this.demoMode;
    this.intakeAnswers = this.initialIntakeAnswers();
    this.contacts = [];
    this.sessionId = null;
    this.sessionStatus = "idle";
    this.stream = null;
    this.syncTimer = null;
    this.startRequestId = 0;
    this.demoTimers = [];
    this.demoRunning = false;
    this.demoAutoStartTimer = null;
    this.personIcons = new Map();
    this.layoutRaf = null;
    this.handleKeydown = this.handleKeydown.bind(this);
    this.handleResize = this.handleResize.bind(this);

    if (this.demoMode) {
      this.resetDemoContacts();
      this.render();
      this.demoAutoStartTimer = window.setTimeout(() => {
        this.demoAutoStartTimer = null;
        this.startDemoSequence();
      }, 500);
    } else {
      this.loadConfirmedContacts();
      this.syncTimer = window.setInterval(
        () => this.loadConfirmedContacts(),
        15000,
      );
    }
    window.addEventListener("keydown", this.handleKeydown);
    window.addEventListener("resize", this.handleResize);
  }

  disconnect() {
    this.startRequestId += 1;
    if (this.syncTimer) {
      window.clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
    this.stopDemoSequence();
    if (this.demoAutoStartTimer) {
      window.clearTimeout(this.demoAutoStartTimer);
      this.demoAutoStartTimer = null;
    }
    if (this.layoutRaf) {
      window.cancelAnimationFrame(this.layoutRaf);
      this.layoutRaf = null;
    }
    window.removeEventListener("keydown", this.handleKeydown);
    window.removeEventListener("resize", this.handleResize);
    this.closeStream();
  }

  handleResize() {
    this.renderStage();
  }

  handleKeydown(event) {
    const key = String(event.key || "").toLowerCase();
    const wantsCancel = (event.ctrlKey || event.metaKey) && key === "c";
    if (!wantsCancel) return;
    if (this.cancelButtonTarget.disabled) return;

    event.preventDefault();
    this.cancelAlert();
  }

  async loadConfirmedContacts() {
    if (this.demoMode) {
      this.resetDemoContacts();
      this.render();
      return;
    }

    if (this.hasLiveCallInProgress()) return;

    const dbContacts = this.loadDbContacts();
    const localContacts = this.loadLocalContacts();
    if (localContacts.length === 0) {
      const previousByPhone = new Map(this.contacts.map((c) => [c.phone, c]));
      this.contacts = dbContacts.map((contact) => {
        const previous = previousByPhone.get(contact.phone);
        return {
          name: contact.name,
          phone: contact.phone,
          callStatus: previous?.callStatus || "ready",
          callSid: previous?.callSid || null,
          lastEventAt: previous?.lastEventAt || null,
        };
      });
      this.render();
      return;
    }

    try {
      const hashes = await Promise.all(
        localContacts.map((contact) => this.hashForPhone(contact.phone)),
      );
      const statusesByHash = await this.bulkLookup(hashes);

      const confirmedLocalContacts = localContacts.filter(
        (contact, index) => statusesByHash[hashes[index]] === "confirmed",
      );
      const combinedContacts = mergeAlertContactsByPhone(
        confirmedLocalContacts,
        dbContacts,
      );
      if (this.hasLiveCallInProgress()) return;
      const previousByPhone = new Map(this.contacts.map((c) => [c.phone, c]));

      this.contacts = combinedContacts.map((contact) => {
        const previous = previousByPhone.get(contact.phone);
        return {
          name: contact.name,
          phone: contact.phone,
          callStatus: previous?.callStatus || "ready",
          callSid: previous?.callSid || null,
          lastEventAt: previous?.lastEventAt || null,
        };
      });
    } catch (error) {
      this.setError("Could not load confirmed contacts.");
      console.error(error);
    }

    this.render();
  }

  hasLiveCallInProgress() {
    if (this.demoMode) return this.demoRunning;
    if (this.stream || this.sessionStatus === "calling") return true;
    return this.contacts.some((contact) =>
      ACTIVE_CALL_STATUSES.has(contact.callStatus),
    );
  }

  loadDbContacts() {
    try {
      const raw = this.element.dataset.alertDbContacts || "[]";
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed)
        ? parsed
            .map(sanitizeLocalContact)
            .filter((contact) => contact.name && contact.phone)
        : [];
    } catch (_) {
      return [];
    }
  }

  resetDemoContacts() {
    const previousByPhone = new Map(this.contacts.map((c) => [c.phone, c]));
    this.contacts = DEMO_FALLBACK_CONTACTS.map((contact) => {
      const previous = previousByPhone.get(contact.phone);
      return {
        name: contact.name,
        phone: contact.phone,
        callStatus: previous?.callStatus || "ready",
        callSid: null,
        lastEventAt: previous?.lastEventAt || null,
      };
    });
  }

  loadLocalContacts() {
    const raw = localStorage.getItem(CONTACT_STORAGE_KEY);
    if (!raw) return [];

    try {
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return parsed
        .map(sanitizeLocalContact)
        .filter((contact) => contact.name && contact.phone);
    } catch (_) {
      return [];
    }
  }

  async hashForPhone(phone) {
    const normalized = normalizePhone(phone);
    if (!normalized) throw new Error("Invalid phone number");
    return sha256Hex(`${this.clientUid}${normalized}`);
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
    if (!response.ok)
      throw new Error(`bulk_lookup failed (${response.status})`);
    const payload = await response.json();
    return payload.consents || {};
  }

  async startAlert() {
    if (!this.demoMode && !this.promptCompleted) {
      this.autoStartRequested = true;
      this.autoStartAttempted = false;
      this.alertButtonTarget.hidden = true;
      this.showPrompt();
      return;
    }

    if (this.contacts.length === 0) {
      this.setError("No confirmed contacts available.");
      return;
    }

    if (this.demoMode) {
      this.startDemoSequence();
      return;
    }

    this.clearError();
    this.alertButtonTarget.disabled = true;
    const requestId = ++this.startRequestId;

    this.contacts = this.contacts.map((contact) => ({
      ...contact,
      callStatus: "queued",
      callSid: null,
      lastEventAt: new Date().toISOString(),
    }));
    this.render();

    const payload = {
      numbers: this.contacts.map((contact) => contact.phone),
      room_name: `alert-${Date.now()}`,
      caller_name: "Alert",
    };

    try {
      const response = await fetch("/api/call_everyone", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        let serverMessage = `call_everyone failed (${response.status})`;
        try {
          const payload = await response.json();
          serverMessage =
            payload?.message ||
            payload?.error ||
            payload?.status ||
            serverMessage;
        } catch (_) {
          // Ignore JSON parse errors and keep generic message.
        }
        throw new Error(serverMessage);
      }

      const data = await response.json();

      if (requestId !== this.startRequestId) {
        const staleCallSids = (data.contacts || [])
          .map((contact) => contact.call_sid)
          .filter(Boolean);
        if (staleCallSids.length > 0) {
          try {
            await fetch("/api/hangup_calls", {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Accept: "application/json",
              },
              body: JSON.stringify({ call_sids: staleCallSids }),
            });
          } catch (hangupError) {
            console.error(hangupError);
          }
        }
        return;
      }

      this.sessionId = data.session_id || null;
      this.sessionStatus = data.session_status || data.status || "calling";
      this.applyContactsFromServer(data.contacts || []);
      if (this.sessionId) {
        this.openStream(
          data.stream_url || `/api/calls/sessions/${this.sessionId}/stream`,
        );
      }
    } catch (error) {
      if (requestId !== this.startRequestId) return;
      this.setError(error?.message || "Could not start alert calls.");
      this.alertButtonTarget.disabled = false;
      this.alertButtonTarget.hidden = false;
      console.error(error);
    }

    this.render();
  }

  async cancelAlert() {
    this.clearError();

    if (this.demoMode) {
      this.cancelDemoSequence();
      return;
    }
    this.startRequestId += 1;

    const callSids = this.contacts
      .filter(
        (contact) =>
          contact.callSid && !FINAL_CALL_STATUSES.has(contact.callStatus),
      )
      .map((contact) => contact.callSid);

    if (callSids.length > 0) {
      try {
        await fetch("/api/hangup_calls", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json",
          },
          body: JSON.stringify({ call_sids: callSids }),
        });
      } catch (error) {
        console.error(error);
      }
    }

    this.contacts = this.contacts.map((contact) =>
      FINAL_CALL_STATUSES.has(contact.callStatus)
        ? contact
        : {
            ...contact,
            callStatus: "canceled",
            lastEventAt: new Date().toISOString(),
          },
    );
    this.sessionId = null;
    this.sessionStatus = "idle";
    this.alertButtonTarget.disabled = false;
    this.alertButtonTarget.hidden = false;
    this.autoStartRequested = false;
    this.autoStartAttempted = false;
    this.promptCompleted = false;
    this.promptStepIndex = 0;
    this.intakeAnswers = this.initialIntakeAnswers();
    this.hidePrompt();
    this.closeStream();
    this.render();
  }

  startDemoSequence() {
    if (this.demoAutoStartTimer) {
      window.clearTimeout(this.demoAutoStartTimer);
      this.demoAutoStartTimer = null;
    }
    this.stopDemoSequence();
    this.clearError();

    this.demoRunning = true;
    this.sessionStatus = "calling";
    this.alertButtonTarget.disabled = true;
    this.cancelButtonTarget.disabled = false;

    this.contacts = this.contacts.map((contact) => ({
      ...contact,
      callStatus: "calling",
      callSid: null,
      lastEventAt: new Date().toISOString(),
    }));
    this.render();

    const total = this.contacts.length;
    if (total === 0) {
      this.finishDemoSequence();
      return;
    }

    const allIndexes = Array.from({ length: total }, (_, i) => i);
    const shuffledIndexes = this.shuffleIndexes(allIndexes);
    const acceptCount = this.randomInt(1, Math.min(4, total));
    const remainingAfterAccept = total - acceptCount;
    const declineCount =
      remainingAfterAccept > 0
        ? this.randomInt(1, Math.min(3, remainingAfterAccept))
        : 0;

    const acceptedIndexes = shuffledIndexes.slice(0, acceptCount);
    const declinedIndexes = shuffledIndexes.slice(
      acceptCount,
      acceptCount + declineCount,
    );

    declinedIndexes.forEach((contactIndex) => {
      this.scheduleDemo(this.randomInt(1200, 12500), () => {
        this.setContactStatusByIndex(
          contactIndex,
          "declined",
          OPEN_CALL_STATUSES,
        );
      });
    });

    acceptedIndexes.forEach((contactIndex, order) => {
      const minAcceptMs = 10000 + order * 320;
      const maxAcceptMs = Math.min(14500, minAcceptMs + 900);
      this.scheduleDemo(this.randomInt(minAcceptMs, maxAcceptMs), () => {
        this.setContactStatusByIndex(
          contactIndex,
          "joined",
          OPEN_CALL_STATUSES,
        );
      });
    });

    this.scheduleDemo(15000, () => {
      const remainingIndexes = this.shuffleIndexes(
        this.contacts
          .map((contact, index) => ({ contact, index }))
          .filter(
            ({ contact }) =>
              stageBucketForStatus(contact.callStatus) === "calling",
          )
          .map(({ index }) => index),
      );

      remainingIndexes.forEach((contactIndex, step) => {
        this.scheduleDemo(step * 550, () => {
          this.setContactStatusByIndex(
            contactIndex,
            "no_answer",
            OPEN_CALL_STATUSES,
          );
        });
      });

      this.scheduleDemo(remainingIndexes.length * 550 + 700, () => {
        this.finishDemoSequence();
      });
    });
  }

  setContactStatusByIndex(contactIndex, status, allowedCurrentStatuses = null) {
    if (contactIndex < 0 || contactIndex >= this.contacts.length) return;

    this.contacts = this.contacts.map((contact, index) => {
      if (index !== contactIndex) return contact;
      if (
        allowedCurrentStatuses &&
        !allowedCurrentStatuses.has(contact.callStatus)
      ) {
        return contact;
      }
      return {
        ...contact,
        callStatus: status,
        lastEventAt: new Date().toISOString(),
      };
    });
    this.render();
  }

  randomInt(min, max) {
    if (max <= min) return min;
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  shuffleIndexes(indexes) {
    const copy = [...indexes];
    for (let i = copy.length - 1; i > 0; i -= 1) {
      const j = Math.floor(Math.random() * (i + 1));
      [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
  }

  scheduleDemo(delayMs, callback) {
    const timerId = window.setTimeout(() => {
      this.demoTimers = this.demoTimers.filter((id) => id !== timerId);
      callback();
    }, delayMs);
    this.demoTimers.push(timerId);
  }

  finishDemoSequence() {
    this.stopDemoSequence();
    this.sessionStatus = "completed";
    this.render();
  }

  cancelDemoSequence() {
    this.stopDemoSequence();
    this.sessionStatus = "idle";
    this.contacts = this.contacts.map((contact) =>
      contact.callStatus === "joined" || contact.callStatus === "declined"
        ? contact
        : {
            ...contact,
            callStatus: "canceled",
            lastEventAt: new Date().toISOString(),
          },
    );
    this.render();
  }

  stopDemoSequence() {
    this.demoTimers.forEach((timerId) => window.clearTimeout(timerId));
    this.demoTimers = [];
    this.demoRunning = false;
  }

  openStream(url) {
    this.closeStream();

    const stream = new EventSource(url);
    this.stream = stream;

    stream.addEventListener("snapshot", (event) => {
      try {
        const payload = JSON.parse(event.data);
        this.sessionStatus = payload.status || this.sessionStatus;
        this.applyContactsFromServer(payload.contacts || []);
        if (this.sessionStatus === "completed") {
          this.closeStream();
        }
        this.render();
      } catch (error) {
        console.error(error);
      }
    });

    stream.addEventListener("contact_update", (event) => {
      try {
        const payload = JSON.parse(event.data);
        this.applyContactUpdate(payload);
        this.render();
      } catch (error) {
        console.error(error);
      }
    });

    stream.addEventListener("session_update", (event) => {
      try {
        const payload = JSON.parse(event.data);
        this.sessionStatus = payload.status || this.sessionStatus;
        if (this.sessionStatus === "completed") {
          this.alertButtonTarget.disabled = false;
          this.alertButtonTarget.hidden = false;
          this.autoStartRequested = false;
          this.autoStartAttempted = false;
          this.cancelButtonTarget.disabled = true;
          this.closeStream();
        }
        this.render();
      } catch (error) {
        console.error(error);
      }
    });

    stream.addEventListener("session_end", () => {
      this.closeStream();
    });

    stream.onerror = () => {
      if (stream.readyState === EventSource.CLOSED) {
        this.closeStream();
      }
    };
  }

  closeStream() {
    if (this.stream) {
      this.stream.close();
      this.stream = null;
    }
  }

  applyContactsFromServer(serverContacts) {
    const byPhone = new Map(this.contacts.map((c) => [c.phone, c]));
    serverContacts.forEach((entry) => {
      const phone = normalizePhone(entry.phone_number || entry.number);
      if (!phone) return;

      if (!byPhone.has(phone)) {
        byPhone.set(phone, {
          name: entry.name || phone,
          phone,
          callStatus: "ready",
          callSid: null,
          lastEventAt: null,
        });
      }

      const current = byPhone.get(phone);
      byPhone.set(phone, {
        ...current,
        callStatus: entry.status || current.callStatus,
        callSid: entry.call_sid || current.callSid,
        lastEventAt: entry.last_event_at || current.lastEventAt,
      });
    });
    this.contacts = Array.from(byPhone.values());

    const hasActive = this.contacts.some((contact) =>
      ACTIVE_CALL_STATUSES.has(contact.callStatus),
    );
    this.cancelButtonTarget.disabled = !hasActive;
    if (!hasActive && this.sessionStatus !== "calling") {
      this.alertButtonTarget.disabled = false;
    }
  }

  maybeAutoStart() {
    if (this.demoMode) return;
    if (!this.autoStartRequested) return;
    if (this.autoStartAttempted) return;
    if (this.sessionStatus !== "idle") return;
    if (!this.promptCompleted) {
      this.showPrompt();
      return;
    }

    this.autoStartAttempted = true;
    this.startAlert();
  }

  initialIntakeAnswers() {
    return {
      feeling: this.pageParams.get("feeling") || "overwhelmed",
      trigger: this.pageParams.get("trigger") || "unspecified",
      urgency: this.normalizeUrgency(this.pageParams.get("urgency")),
    };
  }

  normalizeUrgency(rawValue) {
    const value = String(rawValue || "").toLowerCase();
    if (["low", "moderate", "high"].includes(value)) return value;
    return "high";
  }

  choosePromptOption(event) {
    const button = event.currentTarget;
    const key = button.dataset.key;
    const value = button.dataset.value;
    if (!key || !value) return;

    this.intakeAnswers[key] =
      key === "urgency" ? this.normalizeUrgency(value) : value;

    if (this.promptStepIndex >= this.promptSteps.length - 1) {
      this.promptCompleted = true;
      this.hidePrompt();
      this.maybeAutoStart();
      return;
    }

    this.promptStepIndex += 1;
    this.renderIntakePrompt();
  }

  skipPrompts() {
    this.promptCompleted = true;
    this.hidePrompt();
    this.maybeAutoStart();
  }

  showPrompt() {
    if (this.promptCompleted || !this.hasIntakeCardTarget) return;
    if (this.hasAlertButtonTarget) this.alertButtonTarget.hidden = true;
    this.intakeCardTarget.hidden = false;
    this.renderIntakePrompt();
  }

  hidePrompt() {
    if (!this.hasIntakeCardTarget) return;
    this.intakeCardTarget.hidden = true;
  }

  renderIntakePrompt() {
    if (!this.hasIntakeCardTarget) return;
    const step = this.promptSteps[this.promptStepIndex];
    if (!step) return;

    this.intakeProgressTarget.textContent = `Step ${this.promptStepIndex + 1} of ${this.promptSteps.length}`;
    this.intakeTitleTarget.textContent = step.title;
    this.intakeHintTarget.textContent = step.hint;
    this.intakeOptionsTarget.innerHTML = step.options
      .map((option) => {
        const selected = this.intakeAnswers[step.key] === option;
        return `
          <button
            type="button"
            class="studio-alert-chip alert-intake__option${selected ? " is-primary" : ""}"
            data-key="${escapeHtml(step.key)}"
            data-value="${escapeHtml(option)}"
            data-action="click->alert#choosePromptOption"
          >
            ${escapeHtml(this.promptOptionLabel(option))}
          </button>
        `;
      })
      .join("");
  }

  promptOptionLabel(value) {
    return String(value)
      .replaceAll("_", " ")
      .replace(/\b\w/g, (char) => char.toUpperCase());
  }

  applyContactUpdate(entry) {
    const phone = normalizePhone(entry.phone_number);
    if (!phone) return;
    this.contacts = this.contacts.map((contact) => {
      if (contact.phone !== phone) return contact;
      return {
        ...contact,
        callStatus: entry.status || contact.callStatus,
        callSid: entry.call_sid || contact.callSid,
        lastEventAt: entry.last_event_at || contact.lastEventAt,
      };
    });

    const hasActive = this.contacts.some((contact) =>
      ACTIVE_CALL_STATUSES.has(contact.callStatus),
    );
    this.cancelButtonTarget.disabled = !hasActive;
    if (!hasActive && this.sessionStatus !== "calling") {
      this.alertButtonTarget.disabled = false;
    }
  }

  setError(message) {
    this.errorTarget.textContent = message;
  }

  clearError() {
    this.errorTarget.textContent = "";
  }

  iconKeyForContact(contact) {
    return contact.phone || contact.name;
  }

  buildPersonIcon(contact) {
    const icon = document.createElement("span");
    icon.className = "alert-person-icon";
    icon.title = contact.name;
    icon.innerHTML = PERSON_ICON_SVG;
    return icon;
  }

  syncIconElements() {
    if (!this.hasIconLayerTarget) return;

    const neededKeys = new Set(
      this.contacts.map((c) => this.iconKeyForContact(c)),
    );

    this.contacts.forEach((contact) => {
      const key = this.iconKeyForContact(contact);
      if (this.personIcons.has(key)) return;

      const icon = this.buildPersonIcon(contact);
      icon.dataset.key = key;
      this.iconLayerTarget.appendChild(icon);
      this.personIcons.set(key, icon);
    });

    Array.from(this.personIcons.entries()).forEach(([key, icon]) => {
      if (neededKeys.has(key)) return;
      icon.remove();
      this.personIcons.delete(key);
    });
  }

  renderStage() {
    if (!this.hasStageTarget) return;

    const buckets = {
      calling: [],
      declined: [],
      no_response: [],
      accepted: [],
    };

    this.contacts.forEach((contact) => {
      const bucket = stageBucketForStatus(contact.callStatus);
      if (!bucket) return;
      buckets[bucket].push(contact);
    });

    this.callingCountTarget.textContent = String(buckets.calling.length);
    this.declinedCountTarget.textContent = String(buckets.declined.length);
    this.noResponseCountTarget.textContent = String(buckets.no_response.length);
    this.acceptedCountTarget.textContent = String(buckets.accepted.length);

    this.syncIconElements();

    if (this.layoutRaf) {
      window.cancelAnimationFrame(this.layoutRaf);
    }
    this.layoutRaf = window.requestAnimationFrame(() => {
      this.contacts.forEach((contact) => {
        const key = this.iconKeyForContact(contact);
        const icon = this.personIcons.get(key);
        if (!icon) return;
        const bucket = stageBucketForStatus(contact.callStatus);
        if (!bucket) {
          icon.style.opacity = "0";
        }
      });

      const stageRect = this.stageTarget.getBoundingClientRect();
      const zoneRects = {
        calling: this.callingZoneTarget.getBoundingClientRect(),
        declined: this.declinedZoneTarget.getBoundingClientRect(),
        no_response: this.noResponseZoneTarget.getBoundingClientRect(),
        accepted: this.acceptedZoneTarget.getBoundingClientRect(),
      };

      Object.entries(buckets).forEach(([bucket, contacts]) => {
        const zoneRect = zoneRects[bucket];
        const horizontalGap = 34;
        const verticalGap = 42;
        const baseX = zoneRect.left - stageRect.left + 12;
        const baseY = zoneRect.top - stageRect.top + 12;
        const columns = Math.max(
          1,
          Math.floor((zoneRect.width - 24) / horizontalGap),
        );

        contacts.forEach((contact, index) => {
          const key = this.iconKeyForContact(contact);
          const icon = this.personIcons.get(key);
          if (!icon) return;

          const column = index % columns;
          const row = Math.floor(index / columns);
          const x = Math.round(baseX + column * horizontalGap);
          const y = Math.round(baseY + row * verticalGap);

          icon.style.transform = `translate(${x}px, ${y}px)`;
          icon.style.opacity = "1";
          icon.classList.toggle("is-calling", bucket === "calling");
          icon.classList.toggle("is-declined", bucket === "declined");
          icon.classList.toggle("is-no-response", bucket === "no_response");
          icon.classList.toggle("is-accepted", bucket === "accepted");
        });
      });
    });
  }

  sortedContactsForTable() {
    return [...this.contacts].sort((a, b) => {
      const rankDiff =
        statusSortRank(a.callStatus) - statusSortRank(b.callStatus);
      if (rankDiff !== 0) return rankDiff;
      return a.name.localeCompare(b.name);
    });
  }

  renderTableRows() {
    const previousRects = new Map();
    Array.from(
      this.tbodyTarget.querySelectorAll("tr[data-contact-key]"),
    ).forEach((row) => {
      previousRects.set(row.dataset.contactKey, row.getBoundingClientRect());
    });

    const sortedContacts = this.sortedContactsForTable();
    this.tbodyTarget.innerHTML = sortedContacts
      .map((contact) => {
        const label = callStatusLabel(contact.callStatus);
        const badgeClass = statusClass(contact.callStatus);
        const key = this.iconKeyForContact(contact);
        return `
          <tr class="alert-contact-row" data-contact-key="${escapeHtml(key)}">
            <td>${escapeHtml(contact.name)}</td>
            <td><span class="studio-status ${badgeClass}">${escapeHtml(label)}</span></td>
          </tr>
        `;
      })
      .join("");

    const newRows = Array.from(
      this.tbodyTarget.querySelectorAll("tr[data-contact-key]"),
    );
    window.requestAnimationFrame(() => {
      newRows.forEach((row) => {
        if (typeof row.animate !== "function") return;

        const key = row.dataset.contactKey;
        const previous = previousRects.get(key);
        const next = row.getBoundingClientRect();

        if (!previous) {
          row.animate(
            [
              { opacity: 0, transform: "translateY(6px)" },
              { opacity: 1, transform: "translateY(0)" },
            ],
            { duration: 260, easing: "ease-out" },
          );
          return;
        }

        const deltaY = previous.top - next.top;
        if (Math.abs(deltaY) < 0.5) return;

        row.animate(
          [
            { transform: `translateY(${deltaY}px)` },
            { transform: "translateY(0)" },
          ],
          { duration: 420, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)" },
        );
      });
    });
  }

  updateAlertButtonLabel(total) {
    const displayCount = total > 0 ? total : this.dbContactCount;
    const suffix = displayCount === 1 ? "" : "S";
    this.alertButtonTarget.textContent = `CALL ${displayCount} CONTACT${suffix}`;
  }

  render() {
    const total = this.contacts.length;
    const hasActive = this.contacts.some((c) =>
      ACTIVE_CALL_STATUSES.has(c.callStatus),
    );
    this.updateAlertButtonLabel(total);
    const shouldHideAlertButton =
      !this.demoMode &&
      !this.promptCompleted &&
      this.hasIntakeCardTarget &&
      !this.intakeCardTarget.hidden;
    this.alertButtonTarget.hidden = shouldHideAlertButton;

    if (total === 0) {
      this.alertButtonTarget.disabled = this.demoMode;
      this.cancelButtonTarget.disabled = true;
      this.tbodyTarget.innerHTML = `
        <tr>
          <td colspan="2" class="studio-empty">No confirmed contacts available.</td>
        </tr>
      `;
      this.renderStage();
      if (this.autoStartRequested && !this.promptCompleted) this.showPrompt();
      return;
    }

    if (this.demoMode) {
      this.alertButtonTarget.disabled = this.demoRunning;
      this.cancelButtonTarget.disabled = !this.demoRunning;
    } else if (!hasActive && this.sessionStatus !== "calling") {
      this.alertButtonTarget.disabled = false;
      this.cancelButtonTarget.disabled = true;
    } else if (hasActive) {
      this.cancelButtonTarget.disabled = false;
    }

    this.renderStage();
    this.renderTableRows();
    if (this.autoStartRequested && !this.promptCompleted) this.showPrompt();
  }
}
