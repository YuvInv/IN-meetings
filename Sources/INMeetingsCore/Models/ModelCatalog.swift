// Adapted from Mila (https://github.com/island-io/mila), © Island Technology, Inc. / Uri Harduf,
// Apache-2.0. Changes: reduced to the single Hebrew model IN-meetings ships and dropped the CoreML
// encoder entry (inert with the Homebrew whisper-cli — see ModelManager). See THIRD_PARTY_NOTICES.md.

import Foundation

/// Catalog of the on-device ASR model(s) the app downloads on first launch.
///
/// We ship exactly one model: the ivrit.ai `large-v3-turbo` GGML, pinned by SHA-256. This is the model
/// the P1 benchmark (ADR-003 / `pipeline/benchmarks/P1-FINDINGS.md`) established the WER/RTF baseline on.
/// Mila ships the full `large-v3` (~3 GB, ~2× slower, somewhat more accurate on Hebrew) — switching
/// would invalidate that baseline, so it is deliberately out of scope here.
public enum ModelCatalog {
    public struct Entry: Sendable, Hashable {
        /// Filename on disk (under `ModelManager.modelsDirectory`).
        public let filename: String
        /// Source download URL (Hugging Face — the same repo `pipeline/benchmarks` pulls from).
        public let url: URL
        /// Lowercase-hex SHA-256 of the file at `url`, pinned so a swapped or corrupt download is
        /// rejected before whisper.cpp ever loads it. Verified against HF's LFS oid on 2026-06-14.
        public let sha256: String
        /// Expected size in bytes — the cheap launch-time "already installed?" check. (A full re-hash
        /// of 1.6 GB on every launch would be wasteful; the SHA gate runs once, right after download.)
        public let sizeBytes: Int
        /// Human-readable label for the menu.
        public let displayName: String
    }

    /// The Hebrew default — `ivrit-ai/whisper-large-v3-turbo-ggml`.
    public static let hebrewTurbo = Entry(
        filename: "ivrit-large-v3-turbo.ggml.bin",
        url: URL(string: "https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin")!,
        sha256: "c8090411113357097bfafc2b8e228ec1639fa7f5fe4ecb5d054ac0ccef8641b1",
        sizeBytes: 1_624_555_275,
        displayName: "ivrit.ai · large-v3-turbo (Hebrew)"
    )

    /// Silero VAD for whisper.cpp — tiny (~865 KB). When installed, the pipeline runs `--vad` so the ASR
    /// only transcribes detected speech: no hallucinated text on within-track silence (the gaps when the
    /// remote side isn't talking). Same Hugging Face source the `pipeline/benchmarks` VAD eval pulled from.
    public static let sileroVad = Entry(
        filename: "ggml-silero-v5.1.2.bin",
        url: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!,
        sha256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf",
        sizeBytes: 885_098,
        displayName: "Silero VAD (whisper.cpp)"
    )
}
