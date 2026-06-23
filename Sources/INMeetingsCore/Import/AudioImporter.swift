import AVFoundation
import Foundation

public enum AudioImportError: Error, LocalizedError {
    case noAudioTrack
    case conversionFailed(String)
    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "The file has no audio track."
        case .conversionFailed(let why): return "Couldn't read the audio: \(why)"
        }
    }
}

/// Decode the audio of any AVFoundation-readable container (m4a/mp3/aac/wav/caf/mp4/mov…) into a
/// 16 kHz mono 16-bit PCM WAV — the format the pipeline's ASR + senko diarizer expect (the live capture
/// already produces 16-bit WAVs). Video containers are handled by reading only their audio track.
public enum AudioImporter {
    public static func convertToWav16kMono(_ input: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioImportError.noAudioTrack
        }

        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
        guard reader.canAdd(readerOutput) else { throw AudioImportError.conversionFailed("reader rejected output") }
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: pcm)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw AudioImportError.conversionFailed("writer rejected input") }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw AudioImportError.conversionFailed(reader.error?.localizedDescription ?? "startReading failed")
        }
        guard writer.startWriting() else {
            throw AudioImportError.conversionFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.in-venture.audio-import")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }
        await writer.finishWriting()

        if reader.status == .failed {
            throw AudioImportError.conversionFailed(reader.error?.localizedDescription ?? "reader failed")
        }
        guard writer.status == .completed else {
            throw AudioImportError.conversionFailed(writer.error?.localizedDescription ?? "writer failed")
        }
    }
}
