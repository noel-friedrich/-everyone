# @everyone

> Disclaimer: This project was built during **HackEurope 2026** by an international team of four.

@everyone helps you reach trusted people quickly in difficult moments.

Live site: **https://at-everyone.help**

## What This Project Is

@everyone is a rapid-contact web app designed for urgent personal situations (mental health crises, safety check-ins, and similar moments where reaching someone fast matters).

From the landing page experience:
- You set up a trusted contact circle.
- You can trigger a one-tap alert flow.
- Confirmed contacts are called in parallel.
- In the meantime, the app gets context on user's situation.
- This info is then summarised by Gemini and fed to responder for context.
- The first person to accept gets connected while others can be stopped.
- Contacts do not need to install an app (phone + SMS/call capability is enough).

## Product Areas

- **Homepage (`/`)**
  - Product explanation, FAQ, and contact form UI.
- **Studio (`/studio`)**
  - Manage trusted contacts and consent status (confirmed / pending / declined).
- **Live Alert (`/alert`)**
  - Trigger calls, monitor live call states, and optionally auto-cancel remaining calls after first acceptance.
- **Consent flow (`/consent`)**
  - Handles contact opt-in / opt-out actions.

## Important Warning (Twilio Disabled)

Twilio access has been disabled to avoid ongoing operating costs.

That means:
- Real outbound calling no longer works.
- Real SMS sending no longer works.
- Twilio-dependent alert behavior is preserved in code, but not active in production without valid Twilio credentials and billing.

## Tech Stack

- **Backend:** Ruby on Rails
- **Frontend:** ERB + Stimulus controllers + vanilla JavaScript/CSS
- **Database:** SQLite (development)
- **Telephony / Messaging integration:** Twilio (currently disabled)
- **Realtime updates:** Server-Sent Events (SSE) stream for live alert session status
- **Context summary:** Gemini APIs (currently disabled)

## How It Works (Technical Outline)

1. A user configures trusted contacts in Studio.
2. Contacts are tracked with consent states (confirmed/pending/declined).
3. Triggering an alert creates a call session via API endpoints.
4. The backend would place parallel outbound Twilio calls and track each contact status.
5. Call lifecycle callbacks update session/contact state in the database.
6. The alert UI consumes session updates (including SSE stream updates) to visualize progress in real time.
7. If enabled, the backend can cancel remaining calls after the first accepted response.

Relevant backend areas include:
- `app/controllers/api/calls_controller.rb`
- `app/services/twilio_service.rb`
- `app/controllers/twilio_voice_controller.rb`
- `config/routes.rb`

## Local Development

### Requirements

- Ruby version from `.ruby-version`
- Bundler
- SQLite

### Setup

1. Install dependencies:
   ```bash
   bundle install
   ```
2. Prepare database:
   ```bash
   bundle exec rails db:prepare
   ```
3. Start the app:
   ```bash
   bin/dev
   ```

### Optional Twilio Environment (if you re-enable calling)

Create a `.env` file with values like:

```env
TWILIO_ACCOUNT_SID=...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=...
TWILIO_API_KEY=...
TWILIO_API_SECRET=...
TWILIO_TWIML_APP_SID=...
PUBLIC_BASE_URL=http://localhost:3000
```

Without valid Twilio credentials + active billing, call/SMS features will fail.

## Contact

For project inquiries:
**noel.friedrich@outlook.de**
