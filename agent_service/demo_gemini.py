from app.clients.gemini_client import GeminiClient
from app.schemas import Intake


def main() -> None:
    client = GeminiClient()
    intake = Intake(
        feeling="overwhelmed",
        trigger="work stress",
        urgency="high",
    )
    summary = client.summarize_intake(intake)
    print("Gemini response:")
    print(summary)


if __name__ == "__main__":
    main()
