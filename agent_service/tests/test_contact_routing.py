import unittest
from datetime import datetime

from app.schemas import Intake, StartActivationRequest
from app.services.contact_routing import ContactRouter


class ContactRouterTest(unittest.TestCase):
    def _payload(
        self,
        *,
        escalation_level: str = "low",
        contacts: list[dict] | None = None,
    ) -> StartActivationRequest:
        return StartActivationRequest(
            activation_id="act_1",
            user_id=42,
            escalation_level=escalation_level,
            intake=Intake(
                feeling="overwhelmed",
                trigger="panic_attack",
                urgency="high",
            ),
            contacts=contacts or [],
        )

    def test_low_escalation_orders_low_then_moderate_then_high(self) -> None:
        router = ContactRouter()
        payload = self._payload(
            escalation_level="low",
            contacts=[
                {
                    "id": 1,
                    "priority": 1,
                    "active": True,
                    "response_count": 1,
                    "miss_count": 0,
                },
                {
                    "id": 2,
                    "priority": 0,
                    "active": True,
                    "response_count": 2,
                    "miss_count": 0,
                    "last_responded_at": datetime.fromisoformat("2026-02-22T11:00:00"),
                },
                {
                    "id": 3,
                    "priority": 2,
                    "active": True,
                    "response_count": 5,
                    "miss_count": 1,
                },
                {
                    "id": 4,
                    "priority": 0,
                    "active": True,
                    "response_count": 2,
                    "miss_count": 0,
                    "last_responded_at": datetime.fromisoformat("2026-02-22T10:00:00"),
                },
                {
                    "id": 5,
                    "priority": 0,
                    "active": False,
                    "response_count": 10,
                    "miss_count": 0,
                },
            ],
        )

        contacts = router.select_contacts(payload)

        self.assertEqual([2, 4, 1, 3], [contact.id for contact in contacts])

    def test_high_escalation_prioritizes_high_contacts_first(self) -> None:
        router = ContactRouter()
        payload = self._payload(
            escalation_level="high",
            contacts=[
                {"id": 1, "priority": 0, "active": True, "response_count": 3, "miss_count": 0},
                {"id": 2, "priority": 2, "active": True, "response_count": 1, "miss_count": 0},
                {"id": 3, "priority": 1, "active": True, "response_count": 2, "miss_count": 0},
            ],
        )

        contacts = router.select_contacts(payload)

        self.assertEqual([2, 3, 1], [contact.id for contact in contacts])

    def test_moderate_escalation_orders_moderate_then_high_then_low(self) -> None:
        router = ContactRouter()
        payload = self._payload(
            escalation_level="moderate",
            contacts=[
                {"id": 1, "priority": 0, "active": True, "response_count": 3, "miss_count": 0},
                {"id": 2, "priority": 1, "active": True, "response_count": 1, "miss_count": 0},
                {"id": 3, "priority": 2, "active": True, "response_count": 2, "miss_count": 0},
            ],
        )

        contacts = router.select_contacts(payload)

        self.assertEqual([2, 3, 1], [contact.id for contact in contacts])

    def test_uses_contact_source_when_payload_has_no_contacts(self) -> None:
        source_calls: list[int] = []

        def contact_source(user_id: int) -> list[dict]:
            source_calls.append(user_id)
            return [
                {"id": 8, "priority": 0, "active": True, "response_count": 2, "miss_count": 1}
            ]

        router = ContactRouter(contact_source=contact_source)
        payload = self._payload(escalation_level="low")

        contacts = router.select_contacts(payload)

        self.assertEqual([42], source_calls)
        self.assertEqual([8], [contact.id for contact in contacts])


if __name__ == "__main__":
    unittest.main()
