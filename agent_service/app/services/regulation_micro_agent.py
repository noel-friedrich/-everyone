from __future__ import annotations

import json
from typing import Literal

from app.clients.gemini_client import GeminiClient
from app.schemas import Intake, WaitingRoomPlan
from google import genai
from google.genai import types

Technique = Literal["breathing", "grounding", "reassurance", "reset", "presence"]
Pacing = Literal["slow", "steady", "direct"]


class RegulationMicroAgent:
    """
    Generates a short waiting-room script to help the activating user regulate
    while contacts are being called.

    Design goals:
    - deterministic fallback
    - optional Gemini enhancement
    - no activation failure if Gemini is unavailable
    """

    def __init__(
        self,
        client: genai.Client | None = None,
        model: str | None = None,
    ) -> None:
        self._client = client
        self._model = model
        self._system = """
You are a calm, non-clinical support assistant embedded in a peer-support calling app.
The app is calling trusted contacts right now; your script is a brief waiting-room message.

Safety and style rules:
- Do NOT provide medical advice, diagnosis, or crisis disclaimers.
- Do NOT mention policies, hotlines, or emergency services.
- Do NOT invent background details.
- Use plain language and short sentences.
- Goal: help the user regulate for about 15-25 seconds while calls ring.

Output format:
- Return ONLY valid JSON matching the schema exactly.
""".strip()

    def build_waiting_room_plan(self, intake: Intake) -> WaitingRoomPlan:
        technique_hint, pacing_hint = self._heuristic(intake)
        fallback_script = self._fallback_script(intake)

        try:
            client, model = self._ensure_client()
            response = client.models.generate_content(
                model=model,
                contents=self._prompt(intake, technique_hint, pacing_hint),
                config=types.GenerateContentConfig(
                    system_instruction=self._system,
                    temperature=0.2,
                    max_output_tokens=220,
                    response_mime_type="application/json",
                ),
            )
            data = json.loads((response.text or "").strip())
            return WaitingRoomPlan(
                script=str(data["script"]).strip()[:450],
                pacing=data["pacing"],
                technique=data["technique"],
            )
        except Exception:
            return WaitingRoomPlan(
                script=fallback_script,
                pacing=pacing_hint,
                technique=technique_hint,
            )

    def _ensure_client(self) -> tuple[genai.Client, str]:
        if self._client is None:
            # Reuse the existing local .env loading behavior.
            GeminiClient._load_local_env()
            helper = GeminiClient()
            self._client = helper.client
            self._model = self._model or helper.model
        return self._client, (self._model or "gemini-2.5-flash")

    def _prompt(self, intake: Intake, technique_hint: Technique, pacing_hint: Pacing) -> str:
        urgency = "moderate" if intake.urgency == "medium" else intake.urgency
        return f"""
Return a waiting-room plan for this user state.

User state:
- feeling: {intake.feeling}
- trigger: {intake.trigger}
- urgency: {urgency}

Heuristic hint (follow unless clearly inappropriate):
- technique: {technique_hint}
- pacing: {pacing_hint}

JSON schema (must match exactly):
{{
  "script": "string",
  "pacing": "slow|steady|direct",
  "technique": "breathing|grounding|reassurance|reset|presence"
}}

Script requirements:
- 2 to 6 sentences total
- Must include: "I’m calling your support network now." (or a very close paraphrase)
- Must include one simple action cue (one breath, feet on floor, unclench jaw, etc.)
- Must include a reassurance that someone will likely connect soon
- Max 450 characters
""".strip()

    @staticmethod
    def _heuristic(intake: Intake) -> tuple[Technique, Pacing]:
        feeling = str(intake.feeling or "").strip().lower()

        if feeling in {"panicky", "panicked", "anxious"}:
            return "breathing", "slow"
        if feeling == "angry":
            return "grounding", "steady"
        if feeling == "lonely":
            return "reassurance", "slow"
        if feeling == "numb":
            return "reset", "steady"
        if intake.urgency == "high":
            return "presence", "direct"
        return "presence", "steady"

    @staticmethod
    def _fallback_script(intake: Intake) -> str:
        feeling = str(intake.feeling or "").strip().lower()

        if feeling in {"panicky", "panicked", "anxious"}:
            return (
                "I’m calling your support network now. "
                "Take one slow breath in, and let it out gently. "
                "You do not have to solve this in this moment. Someone will likely connect soon."
            )
        if feeling == "angry":
            return (
                "I’m calling your support network now. "
                "If you can, feel your feet on the floor and unclench your jaw. "
                "Slow the next breath a little. Someone will likely connect soon."
            )
        if feeling == "lonely":
            return (
                "I’m calling your support network now. "
                "Take one slow breath in and out. "
                "You are not alone in this, and someone will likely connect soon."
            )
        return (
            "I’m calling your support network now. "
            "Take one slow breath in and out. "
            "Stay with that breath for a moment. Someone will likely connect soon."
        )
