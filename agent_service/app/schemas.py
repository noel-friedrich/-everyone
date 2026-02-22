from datetime import datetime, time
from typing import Literal

from pydantic import BaseModel, Field


class Intake(BaseModel):
    feeling: str = Field(..., examples=["overwhelmed"])
    trigger: str = Field(..., examples=["panic_attack"])
    urgency: Literal["low", "medium", "high"]


class Contact(BaseModel):
    id: int
    priority: Literal[0, 1, 2]
    active: bool
    preferred_hours_start: time | None = None
    preferred_hours_end: time | None = None
    timezone: str | None = None
    last_responded_at: datetime | None = None
    response_count: int = Field(default=0, ge=0)
    miss_count: int = Field(default=0, ge=0)


class StartActivationRequest(BaseModel):
    activation_id: str
    user_id: int
    escalation_level: Literal["low", "moderate", "high"] = "low"
    intake: Intake
    contacts: list[Contact] = Field(default_factory=list)


class StartActivationResponse(BaseModel):
    activation_id: str
    status: Literal["accepted"]
    summary_text: str
    started_at: datetime
    routed_contacts: list[Contact] = Field(default_factory=list)
