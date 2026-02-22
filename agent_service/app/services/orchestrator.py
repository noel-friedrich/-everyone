from datetime import datetime, timezone

from app.clients.gemini_client import GeminiClient
from app.clients.twilio_client import TwilioClient
from app.schemas import StartActivationRequest, StartActivationResponse
from app.services.contact_routing import ContactRouter


class ActivationOrchestrator:
    def __init__(
        self,
        gemini_client: GeminiClient | None = None,
        twilio_client: TwilioClient | None = None,
        contact_router: ContactRouter | None = None,
    ) -> None:
        self.gemini_client = gemini_client or GeminiClient()
        self.twilio_client = twilio_client or TwilioClient()
        self.contact_router = contact_router or ContactRouter()

    def start(self, payload: StartActivationRequest) -> StartActivationResponse:
        """
        Entry point for business logic.

        Current template flow:
        - Build context summary from intake.
        - Select contacts using deterministic routing.
        - Trigger Twilio outbound orchestration (placeholder).
        """
        summary = self.gemini_client.summarize_intake(payload.intake)
        contacts = self.contact_router.select_contacts(payload)
        self.twilio_client.start_outbound_flow(
            activation_id=payload.activation_id,
            user_id=payload.user_id,
        )

        return StartActivationResponse(
            activation_id=payload.activation_id,
            status="accepted",
            summary_text=summary,
            started_at=datetime.now(timezone.utc),
            routed_contacts=contacts,
        )
