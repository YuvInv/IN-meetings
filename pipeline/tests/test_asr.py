"""whisper.cpp command building + Silero VAD model resolution."""

from __future__ import annotations

from pathlib import Path

from in_meetings_pipeline.asr import resolve_vad_model, whisper_cmd


def test_whisper_cmd_without_vad() -> None:
    cmd = whisper_cmd(Path("m.bin"), Path("a.wav"), Path("o"), "he", None)
    assert "--vad" not in cmd
    assert "-bs" in cmd and "-oj" in cmd


def test_whisper_cmd_with_vad() -> None:
    cmd = whisper_cmd(Path("m.bin"), Path("a.wav"), Path("o"), "he", Path("vad.bin"))
    assert "--vad" in cmd
    assert cmd[cmd.index("--vad-model") + 1] == "vad.bin"


def test_resolve_vad_model_env_override(tmp_path: Path, monkeypatch) -> None:
    vad = tmp_path / "v.bin"
    vad.write_bytes(b"x")
    monkeypatch.setenv("IN_MEETINGS_VAD_MODEL", str(vad))
    assert resolve_vad_model() == vad


def test_resolve_vad_model_missing_path_is_none(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("IN_MEETINGS_VAD_MODEL", str(tmp_path / "nope.bin"))
    assert resolve_vad_model() is None
