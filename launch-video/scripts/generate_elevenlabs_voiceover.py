from __future__ import annotations

import os
import pathlib
import sys

from dotenv import load_dotenv
from elevenlabs import VoiceSettings
from elevenlabs.client import ElevenLabs


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "public" / "audio" / "voiceover-script.txt"
OUT_PATH = ROOT / "public" / "audio" / "studyshare-launch-voiceover.mp3"

# Natural Indian English female voice from the ElevenLabs voice library.
# Override with ELEVENLABS_VOICE_ID if you prefer a saved voice from your account.
DEFAULT_VOICE_ID = "4Mhjd1Q9JRWcKfDQvn26"
DEFAULT_MODEL_ID = "eleven_v3"


def main() -> int:
    load_dotenv(ROOT / ".env")
    api_key = os.getenv("ELEVENLABS_API_KEY", "").strip()
    if not api_key:
        print("ELEVENLABS_API_KEY is not set.", file=sys.stderr)
        return 2

    text = SCRIPT_PATH.read_text(encoding="utf-8").strip()
    if not text:
        print(f"Voiceover script is empty: {SCRIPT_PATH}", file=sys.stderr)
        return 2

    voice_id = os.getenv("ELEVENLABS_VOICE_ID", DEFAULT_VOICE_ID).strip()
    model_id = os.getenv("ELEVENLABS_MODEL_ID", DEFAULT_MODEL_ID).strip()

    client = ElevenLabs(api_key=api_key)
    audio = client.text_to_speech.convert(
        text=text,
        voice_id=voice_id,
        model_id=model_id,
        output_format="mp3_44100_128",
        voice_settings=VoiceSettings(
            stability=0.38,
            similarity_boost=0.78,
            style=0.55,
            speed=0.96,
            use_speaker_boost=True,
        ),
        apply_text_normalization="on",
    )

    encoded = b"".join(chunk for chunk in audio if chunk)
    if not encoded:
        print("ElevenLabs returned no audio.", file=sys.stderr)
        return 1

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_bytes(encoded)

    print(f"Wrote {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
