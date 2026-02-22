from collections.abc import Callable
from datetime import datetime
from typing import Any

from app.schemas import Contact, StartActivationRequest


class ContactRouter:
    ESCALATION_PRIORITY_ORDER = {
        "low": (0, 1, 2),
        "moderate": (1, 2, 0),
        "high": (2, 1, 0),
    }

    def __init__(
        self,
        contact_source: Callable[[int], list[Contact | dict[str, Any]]] | None = None,
    ) -> None:
        self._contact_source = contact_source

    def select_contacts(self, payload: StartActivationRequest) -> list[Contact]:
        contacts = self._load_contacts(payload)
        eligible = self._filter_by_escalation(contacts, payload.escalation_level)
        return sorted(eligible, key=lambda contact: self._sort_key(contact, payload.escalation_level))

    def _load_contacts(self, payload: StartActivationRequest) -> list[Contact]:
        if payload.contacts:
            source_contacts: list[Contact | dict[str, Any]] = payload.contacts
        elif self._contact_source is not None:
            source_contacts = self._contact_source(payload.user_id)
        else:
            source_contacts = []

        return [self._coerce_contact(contact) for contact in source_contacts]

    def _coerce_contact(self, contact: Contact | dict[str, Any]) -> Contact:
        if isinstance(contact, Contact):
            return contact
        return Contact.model_validate(contact)

    def _filter_by_escalation(
        self,
        contacts: list[Contact],
        escalation_level: str,
    ) -> list[Contact]:
        allowed_priorities = set(self.ESCALATION_PRIORITY_ORDER[escalation_level])
        return [
            contact
            for contact in contacts
            if contact.active and contact.priority in allowed_priorities
        ]

    def _sort_key(
        self,
        contact: Contact,
        escalation_level: str,
    ) -> tuple[int, float, float, int, int]:
        priority_rank = self._priority_rank(contact.priority, escalation_level)
        return (
            priority_rank,
            -self._reliability_score(contact),
            -self._timestamp_or_min(contact.last_responded_at),
            -contact.response_count,
            contact.id,
        )

    def _priority_rank(self, priority: int, escalation_level: str) -> int:
        order = self.ESCALATION_PRIORITY_ORDER[escalation_level]
        return order.index(priority) if priority in order else len(order)

    def _reliability_score(self, contact: Contact) -> float:
        attempts = contact.response_count + contact.miss_count
        if attempts <= 0:
            return 0.0
        return contact.response_count / attempts

    def _timestamp_or_min(self, value: datetime | None) -> float:
        if value is None:
            return float("-inf")
        return value.timestamp()
