import unittest

from app.schemas import Intake
from app.services.regulation_micro_agent import RegulationMicroAgent


class RegulationMicroAgentTest(unittest.TestCase):
    def _intake(self, feeling: str, urgency: str = "high") -> Intake:
        return Intake(feeling=feeling, trigger="work", urgency=urgency)

    def test_panicked_prefers_breathing_slow(self) -> None:
        technique, pacing = RegulationMicroAgent._heuristic(self._intake("panicked"))
        self.assertEqual(("breathing", "slow"), (technique, pacing))

    def test_angry_prefers_grounding(self) -> None:
        technique, pacing = RegulationMicroAgent._heuristic(self._intake("angry", "medium"))
        self.assertEqual(("grounding", "steady"), (technique, pacing))

    def test_lonely_fallback_mentions_not_alone(self) -> None:
        script = RegulationMicroAgent._fallback_script(self._intake("lonely", "low"))
        self.assertIn("I’m calling your support network now.", script)
        self.assertIn("not alone", script.lower())

    def test_fallback_plan_is_returned_when_generation_fails(self) -> None:
        agent = RegulationMicroAgent()
        agent._ensure_client = lambda: (_ for _ in ()).throw(RuntimeError("boom"))  # type: ignore[attr-defined]

        plan = agent.build_waiting_room_plan(self._intake("anxious"))

        self.assertEqual("breathing", plan.technique)
        self.assertEqual("slow", plan.pacing)
        self.assertIn("support network", plan.script)


if __name__ == "__main__":
    unittest.main()
