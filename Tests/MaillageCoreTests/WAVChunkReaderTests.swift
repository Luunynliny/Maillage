import AVFoundation
import Testing

@testable import MaillageCore

/// `WAVChunkReader` is the whole-file counterpart to what `WAVSampleReader` used to do for one
/// time range — reads a track's WAV file in bounded chunks, never the whole thing into memory at
/// once, so feeding a long meeting's audio into Nemotron stays constant-memory the same way
/// `AsrManager.transcribeDiskBacked` did for Parakeet.
@Suite("WAV chunk reader")
struct WAVChunkReaderTests {
    /// Writes `frameCount` frames of a rising ramp (so chunk boundaries are checkable, unlike
    /// silence) to a fresh 16kHz mono WAV file — the same sample rate `mic.wav`/`system.wav` are
    /// recorded at. Written on-disk as 16-bit PCM (same as a real recording), but the write
    /// itself must go through `AVAudioFile`'s own `processingFormat` — always Float32, regardless
    /// of the on-disk format passed via `settings` — not the on-disk format directly; a buffer in
    /// any other format crashes `AVAudioFile.write(from:)`.
    private func writeRampWAV(frameCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("wav")
        let onDiskFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let file = try AVAudioFile(forWriting: url, settings: onDiskFormat.settings)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frameCount)))
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = try #require(buffer.floatChannelData?[0])
        // Normalized (0..<1) and strictly increasing with frame index — Int16 on disk quantizes
        // it slightly, but a value this far apart from its neighbors survives the round trip well
        // above that quantization noise, unlike raw frame indices, which would clip to the
        // Int16 writer's [-1, 1] range and all read back identical.
        for i in 0..<frameCount {
            channel[i] = Float(i) / Float(frameCount)
        }
        try file.write(from: buffer)
        return url
    }

    @Test("Reads the whole file across several chunks, in order, with none dropped")
    func readsWholeFileAcrossChunks() async throws {
        let frameCount = 10_000
        let url = try writeRampWAV(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }

        var chunks: [[Float]] = []
        try await WAVChunkReader.forEachChunk(in: url, chunkFrames: 4_000) { chunk in
            chunks.append(chunk)
        }

        // 4000 + 4000 + 2000 — the final chunk is shorter, not padded or dropped.
        #expect(chunks.map(\.count) == [4_000, 4_000, 2_000])
        #expect(chunks.reduce(0) { $0 + $1.count } == frameCount)

        // The first sample of the second chunk should be frame 4000's value (0.4), within
        // Int16 quantization noise — proving no frame was skipped or re-read across the chunk
        // boundary (an off-by-one would land on 0.3999 or 0.4001, well outside the tolerance).
        #expect(abs(chunks[0][0] - 0) < 0.0001)
        #expect(abs(chunks[1][0] - 0.4) < 0.0001)
    }

    @Test("A file shorter than one chunk still comes back as a single chunk")
    func fileShorterThanOneChunk() async throws {
        let url = try writeRampWAV(frameCount: 500)
        defer { try? FileManager.default.removeItem(at: url) }

        var chunks: [[Float]] = []
        try await WAVChunkReader.forEachChunk(in: url, chunkFrames: 4_000) { chunk in
            chunks.append(chunk)
        }

        #expect(chunks.map(\.count) == [500])
    }
}
