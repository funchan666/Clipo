import Foundation
import AVFoundation
import AudioToolbox

/// Repackages the service's unencrypted H.264/AAC transport streams without
/// re-encoding. The OS-managed offline package is never modified or renamed.
enum LessonStreamExport {
    enum Failure: LocalizedError {
        case unsupported, damaged, tooLarge, network, writing
        var errorDescription: String? {
            switch self {
            case .unsupported: return "This stream format cannot be exported. Offline playback is still available."
            case .damaged: return "The video data is incomplete. Please try exporting again."
            case .tooLarge: return "This video is too large to export on this device."
            case .network: return "Video export could not download the stream. Please try again."
            case .writing: return "Video export failed. Please try again."
            }
        }
    }

    // Runs on its own actor, not the main actor that renders/plays the video.
    actor Job {
        private let session: URLSession
        init() {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 90
            session = URLSession(configuration: configuration)
        }

        func convert(_ source: URL, destination: URL,
                     progress: @escaping @Sendable (Double) async -> Void) async throws {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("LessonExport-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: work) }
            var succeeded = false
            defer { if !succeeded { try? FileManager.default.removeItem(at: destination) } }
            let playlist = try await mediaPlaylist(source, depth: 0)
            let spool = work.appendingPathComponent("samples")
            FileManager.default.createFile(atPath: spool.path, contents: nil)
            let sink = try FileHandle(forWritingTo: spool)
            defer { try? sink.close() }
            let transport = Transport(sink: sink)
            var downloaded: Int64 = 0
            for (index, segment) in playlist.segments.enumerated() {
                try Task.checkCancellation()
                let (temporary, response) = try await session.download(from: segment)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Failure.network }
                let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                downloaded += Int64(size)
                // Bound disk and per-segment memory; malformed/live streams cannot grow forever.
                guard size > 0, size <= 32 * 1_024 * 1_024, downloaded <= 1_024 * 1_024 * 1_024 else { throw Failure.tooLarge }
                try transport.consume(Data(contentsOf: temporary, options: .mappedIfSafe))
                await progress(Double(index + 1) / Double(playlist.segments.count) * 0.8)
            }
            try transport.finish()
            try sink.synchronize()
            try await writeMovie(transport, spool: spool, destination: destination, progress: progress)
            try Task.checkCancellation()
            let asset = AVURLAsset(url: destination)
            let duration = try await asset.load(.duration).seconds
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard try await asset.load(.isPlayable), duration.isFinite,
                  abs(duration - playlist.duration) < max(1, playlist.duration * 0.02),
                  !videoTracks.isEmpty, transport.audioSamples.isEmpty || !audioTracks.isEmpty else { throw Failure.damaged }
            succeeded = true
            await progress(1)
        }

        private struct Playlist { let segments: [URL]; let duration: Double }
        private func mediaPlaylist(_ url: URL, depth: Int) async throws -> Playlist {
            guard depth < 4, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw Failure.unsupported }
            let (temporary, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 1_024 * 1_024 else { throw Failure.network }
            let text = try String(contentsOf: temporary, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard lines.first == "#EXTM3U" else { throw Failure.damaged }
            let base = response.url ?? url
            func address(_ line: String) throws -> URL {
                guard let value = URL(string: line, relativeTo: base)?.absoluteURL,
                      ["https", "http"].contains(value.scheme?.lowercased() ?? "") else { throw Failure.unsupported }
                return value
            }
            var variants: [(Int, URL)] = []
            for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
                // This converter handles muxed AVC/AAC variants. Alternate audio,
                // HEVC, byte-range/fMP4, live and encrypted streams stay offline-only.
                guard index + 1 < lines.count, !lines[index + 1].hasPrefix("#"),
                      !line.contains("AUDIO="), !line.contains("hvc1"), !line.contains("hev1") else { continue }
                let rate = line.components(separatedBy: "BANDWIDTH=").dropFirst().first?
                    .prefix(while: { $0.isNumber }).description
                variants.append((Int(rate ?? "") ?? 0, try address(lines[index + 1])))
            }
            if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }) {
                guard let selected = variants.max(by: { $0.0 < $1.0 }) else { throw Failure.unsupported }
                return try await mediaPlaylist(selected.1, depth: depth + 1)
            }
            guard lines.contains("#EXT-X-ENDLIST"), !lines.contains(where: {
                $0.hasPrefix("#EXT-X-KEY:") && !$0.contains("METHOD=NONE") ||
                $0.hasPrefix("#EXT-X-MAP:") || $0.hasPrefix("#EXT-X-BYTERANGE:") ||
                $0 == "#EXT-X-DISCONTINUITY" || $0.hasPrefix("#EXT-X-GAP")
            }) else { throw Failure.unsupported }
            var segments: [URL] = [], duration = 0.0
            var expectingSegment = false
            for line in lines {
                if line.hasPrefix("#EXTINF:") {
                    guard !expectingSegment, let seconds = Double(line.dropFirst(8).split(separator: ",")[0]),
                          seconds.isFinite, seconds > 0 else { throw Failure.damaged }
                    duration += seconds; expectingSegment = true
                } else if !line.hasPrefix("#") {
                    guard expectingSegment else { throw Failure.damaged }
                    segments.append(try address(line)); expectingSegment = false
                }
            }
            guard !expectingSegment, !segments.isEmpty, segments.count <= 1_800, duration <= 3_600 else { throw Failure.unsupported }
            return Playlist(segments: segments, duration: duration)
        }

        private func writeMovie(_ transport: Transport, spool: URL, destination: URL,
                                progress: @escaping @Sendable (Double) async -> Void) async throws {
            guard let videoFormat = transport.videoFormat, !transport.videoSamples.isEmpty else { throw Failure.damaged }
            let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
            defer { if writer.status == .writing { writer.cancelWriting() } }
            writer.shouldOptimizeForNetworkUse = true
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
            guard writer.canAdd(video) else { throw Failure.unsupported }
            writer.add(video)
            var tracks: [(AVAssetWriterInput, CMFormatDescription, [Sample])] = [(video, videoFormat, transport.videoSamples)]
            if let audioFormat = transport.audioFormat, !transport.audioSamples.isEmpty {
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
                guard writer.canAdd(audio) else { throw Failure.unsupported }
                writer.add(audio); tracks.append((audio, audioFormat, transport.audioSamples))
            }
            guard writer.startWriting() else { throw writer.error ?? Failure.writing }
            // Start at the first presentation time. AVC B-frame decode times
            // may be earlier; retaining that negative decode offset avoids an
            // artificial leading audio edit that repeats AAC priming packets.
            let origin = tracks.flatMap { $0.2.prefix(1) }.map(\.pts).min() ?? 0
            writer.startSession(atSourceTime: .zero)
            let reader = try FileHandle(forReadingFrom: spool)
            defer { try? reader.close() }
            var positions = Array(repeating: 0, count: tracks.count)
            var lastProgress = Date()
            let total = tracks.reduce(0) { $0 + $1.2.count }
            while positions.enumerated().contains(where: { $0.element < tracks[$0.offset].2.count }) {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? Failure.writing }
                var advanced = false
                for trackIndex in tracks.indices {
                    let (input, format, samples) = tracks[trackIndex]
                    let index = positions[trackIndex]
                    guard index < samples.count, input.isReadyForMoreMediaData else { continue }
                    let sample = samples[index]
                    let duration: Int64
                    if index + 1 < samples.count { duration = samples[index + 1].dts - sample.dts }
                    else if index > 0 { duration = sample.dts - samples[index - 1].dts }
                    else { duration = sample.duration }
                    guard duration > 0 else { throw Failure.damaged }
                    try reader.seek(toOffset: sample.offset)
                    guard let data = try reader.read(upToCount: sample.size), data.count == sample.size else { throw Failure.damaged }
                    let buffer = try LessonStreamExport.sampleBuffer(data, format: format, pts: sample.pts - origin,
                                                  dts: sample.dts - origin, duration: duration, sync: sample.sync)
                    if input.mediaType == .audio {
                        // These are already encoded AAC packets, with no new
                        // encoder priming/trailing frames to infer or discard.
                        if index == 0 {
                            CMSetAttachment(buffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                                            value: CMTimeCopyAsDictionary(.zero, allocator: kCFAllocatorDefault),
                                            attachmentMode: kCMAttachmentMode_ShouldPropagate)
                        }
                        if index == samples.count - 1 {
                            CMSetAttachment(buffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtEnd,
                                            value: CMTimeCopyAsDictionary(.zero, allocator: kCFAllocatorDefault),
                                            attachmentMode: kCMAttachmentMode_ShouldPropagate)
                        }
                    }
                    guard input.append(buffer) else { throw writer.error ?? Failure.writing }
                    positions[trackIndex] += 1; advanced = true
                    if positions[trackIndex] == samples.count { input.markAsFinished() }
                }
                if advanced {
                    lastProgress = Date()
                    if positions.reduce(0, +) % 50 == 0 { await progress(0.8 + Double(positions.reduce(0, +)) / Double(total) * 0.19) }
                } else {
                    guard Date().timeIntervalSince(lastProgress) < 30 else { throw Failure.writing }
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
            } onCancel: { writer.cancelWriting() }
            try Task.checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? Failure.writing }
        }
    }

    private struct Sample {
        let offset: UInt64, size: Int, pts: Int64, dts: Int64, duration: Int64, sync: Bool
    }

    /// PID/PES assembly survives segment boundaries; sample payloads are spooled
    /// to disk so a long lesson does not accumulate in memory.
    private final class Transport {
        let sink: FileHandle
        var videoFormat: CMFormatDescription?, audioFormat: CMFormatDescription?
        var videoSamples: [Sample] = [], audioSamples: [Sample] = []
        private var offset: UInt64 = 0
        private var pmtPID: Int?, videoPID: Int?, audioPID: Int?
        private var sections: [Int: [UInt8]] = [:], packets: [Int: [UInt8]] = [:], counters: [Int: Int] = [:]
        private var sps: [UInt8]?, pps: [UInt8]?, audioConfiguration: [UInt8]?
        private var previousTime: [Int: Int64] = [:]
        init(sink: FileHandle) { self.sink = sink }

        func consume(_ data: Data) throws {
            let bytes = [UInt8](data)
            guard bytes.count % 188 == 0 else { throw Failure.damaged }
            for start in stride(from: 0, to: bytes.count, by: 188) {
                try Task.checkCancellation()
                guard bytes[start] == 0x47, bytes[start + 1] & 0x80 == 0,
                      bytes[start + 3] & 0xc0 == 0 else { throw Failure.damaged }
                let pid = Int(bytes[start + 1] & 0x1f) << 8 | Int(bytes[start + 2])
                let control = bytes[start + 3] >> 4 & 3
                guard control != 0 else { throw Failure.damaged }
                guard control & 1 != 0, pid == 0 || pid == pmtPID || pid == videoPID || pid == audioPID else { continue }
                var payload = start + 4
                if control & 2 != 0 { payload += 1 + Int(bytes[payload]) }
                guard payload <= start + 188 else { throw Failure.damaged }
                if payload == start + 188 { continue }
                let count = Int(bytes[start + 3] & 15)
                if let previous = counters[pid] {
                    if count == previous { continue } // repeated transport packet
                    guard count == (previous + 1) % 16 else { throw Failure.damaged }
                }
                counters[pid] = count
                let begins = bytes[start + 1] & 0x40 != 0
                let body = Array(bytes[payload..<start + 188])
                if pid == 0 || pid == pmtPID {
                    try section(body, pid: pid, begins: begins)
                } else {
                    if begins {
                        if let previous = packets.removeValue(forKey: pid), !previous.isEmpty { try pes(previous, pid: pid) }
                        packets[pid] = []
                    }
                    guard packets[pid] != nil else { continue }
                    packets[pid]!.append(contentsOf: body)
                    guard packets[pid]!.count <= 4 * 1_024 * 1_024 else { throw Failure.tooLarge }
                    let packet = packets[pid]!
                    if packet.count >= 6 {
                        let length = Int(packet[4]) << 8 | Int(packet[5])
                        if length > 0, packet.count >= length + 6 {
                            try pes(Array(packet.prefix(length + 6)), pid: pid); packets[pid] = nil
                        }
                    }
                }
            }
        }
        func finish() throws {
            for (pid, packet) in packets { try pes(packet, pid: pid) }
            packets.removeAll()
            guard videoFormat != nil, !videoSamples.isEmpty,
                  audioPID == nil || !audioSamples.isEmpty else { throw Failure.damaged }
        }
        private func section(_ bytes: [UInt8], pid: Int, begins: Bool) throws {
            var body = bytes
            if begins {
                guard let pointer = body.first, Int(pointer) + 1 <= body.count else { throw Failure.damaged }
                // PAT/PMT tables in the service stream are each a single section.
                body = Array(body.dropFirst(Int(pointer) + 1)); sections[pid] = []
            }
            guard sections[pid] != nil else { return }
            sections[pid]!.append(contentsOf: body)
            let table = sections[pid]!
            guard table.count >= 3 else { return }
            let length = 3 + (Int(table[1] & 15) << 8 | Int(table[2]))
            guard length <= 1_024, length >= 12 else { throw Failure.damaged }
            guard table.count >= length else { return }
            sections[pid] = nil
            if pid == 0 {
                guard table[0] == 0 else { throw Failure.damaged }
                for i in stride(from: 8, to: length - 4, by: 4) where i + 3 < length - 4 {
                    if table[i] != 0 || table[i + 1] != 0 { pmtPID = Int(table[i + 2] & 31) << 8 | Int(table[i + 3]); break }
                }
            } else {
                guard table[0] == 2, table.count >= 12 else { throw Failure.damaged }
                var i = 12 + (Int(table[10] & 15) << 8 | Int(table[11]))
                while i + 4 < length - 4 {
                    let streamPID = Int(table[i + 1] & 31) << 8 | Int(table[i + 2])
                    switch table[i] {
                    case 0x1b:
                        guard videoPID == nil || videoPID == streamPID else { throw Failure.unsupported }; videoPID = streamPID
                    case 0x0f:
                        guard audioPID == nil || audioPID == streamPID else { throw Failure.unsupported }; audioPID = streamPID
                    case 0x24, 0x03, 0x04, 0x11, 0x81: throw Failure.unsupported
                    default: break // metadata streams do not become movie tracks
                    }
                    i += 5 + (Int(table[i + 3] & 15) << 8 | Int(table[i + 4]))
                }
            }
        }
        private func timestamp(_ b: [UInt8], at i: Int) throws -> Int64 {
            guard i + 4 < b.count, b[i] & 1 == 1, b[i + 2] & 1 == 1, b[i + 4] & 1 == 1 else { throw Failure.damaged }
            return Int64(b[i] & 14) << 29 | Int64(b[i + 1]) << 22 | Int64(b[i + 2] & 254) << 14 | Int64(b[i + 3]) << 7 | Int64(b[i + 4] >> 1)
        }
        private func pes(_ b: [UInt8], pid: Int) throws {
            guard b.count >= 14, b[0] == 0, b[1] == 0, b[2] == 1, b[6] & 0xc0 == 0x80,
                  b[7] & 0x80 != 0, Int(b[8]) + 9 <= b.count else { throw Failure.damaged }
            let declared = Int(b[4]) << 8 | Int(b[5])
            guard declared == 0 || b.count >= declared + 6 else { throw Failure.damaged }
            var pts = try timestamp(b, at: 9)
            var dts = b[7] & 0x40 != 0 ? try timestamp(b, at: 14) : pts
            if let previous = previousTime[pid] {
                let wrap: Int64 = 1 << 33
                while dts < previous - wrap / 2 { dts += wrap; pts += wrap }
                guard dts >= previous else { throw Failure.damaged }
            }
            previousTime[pid] = dts
            let payload = Array(b[(9 + Int(b[8]))..<(declared > 0 ? declared + 6 : b.count)])
            if pid == videoPID { try video(payload, pts: pts, dts: dts) }
            else if pid == audioPID { try audio(payload, pts: pts) }
        }
        private func store(_ data: Data, pts: Int64, dts: Int64, duration: Int64, sync: Bool) throws -> Sample {
            try sink.write(contentsOf: data)
            defer { offset += UInt64(data.count) }
            return Sample(offset: offset, size: data.count, pts: pts, dts: dts, duration: duration, sync: sync)
        }
        private func video(_ bytes: [UInt8], pts: Int64, dts: Int64) throws {
            var starts: [(Int, Int)] = [], i = 0
            while i + 3 <= bytes.count {
                if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 { starts.append((i, i + 3)); i += 3 }
                else if i + 4 <= bytes.count, bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 0, bytes[i + 3] == 1 { starts.append((i, i + 4)); i += 4 }
                else { i += 1 }
            }
            guard !starts.isEmpty else { throw Failure.damaged }
            var data = Data(), key = false, picture = false, delimiters = 0
            for n in starts.indices {
                var end = n + 1 < starts.count ? starts[n + 1].0 : bytes.count
                while end > starts[n].1, bytes[end - 1] == 0 { end -= 1 }
                let nal = Array(bytes[starts[n].1..<end])
                guard let first = nal.first else { continue }
                switch first & 31 {
                case 7:
                    guard sps == nil || sps == nal else { throw Failure.unsupported }; sps = nal
                case 8:
                    guard pps == nil || pps == nal else { throw Failure.unsupported }; pps = nal
                case 9:
                    delimiters += 1; guard delimiters == 1 else { throw Failure.unsupported }
                case 1, 5, 6:
                    if first & 31 != 6 { picture = true }
                    key = key || first & 31 == 5
                    var length = UInt32(nal.count).bigEndian
                    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }; data.append(contentsOf: nal)
                default: break
                }
            }
            if videoFormat == nil, let sps, let pps {
                let status = sps.withUnsafeBufferPointer { s in pps.withUnsafeBufferPointer { p in
                    let pointers = [s.baseAddress!, p.baseAddress!], sizes = [s.count, p.count]
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                        parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4, formatDescriptionOut: &videoFormat)
                } }
                guard status == noErr else { throw Failure.damaged }
            }
            if picture {
                guard videoFormat != nil, !videoSamples.isEmpty || key else { throw Failure.damaged }
                videoSamples.append(try store(data, pts: pts, dts: dts, duration: 3_000, sync: key))
            }
        }
        private func audio(_ b: [UInt8], pts: Int64) throws {
            let rates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]
            var i = 0, frame = 0
            while i < b.count {
                guard i + 7 <= b.count, b[i] == 255, b[i + 1] & 0xf6 == 0xf0 else { throw Failure.damaged }
                let profile = Int(b[i + 2] >> 6) + 1, rateIndex = Int(b[i + 2] >> 2 & 15)
                let channels = Int(b[i + 2] & 1) << 2 | Int(b[i + 3] >> 6)
                let length = Int(b[i + 3] & 3) << 11 | Int(b[i + 4]) << 3 | Int(b[i + 5] >> 5)
                let header = b[i + 1] & 1 == 1 ? 7 : 9
                guard profile == 2, rateIndex < rates.count, (1...2).contains(channels),
                      b[i + 6] & 3 == 0, length > header, i + length <= b.count else { throw Failure.unsupported }
                let cookie: [UInt8] = [UInt8(profile << 3 | rateIndex >> 1), UInt8((rateIndex & 1) << 7 | channels << 3)]
                guard audioConfiguration == nil || audioConfiguration == cookie else { throw Failure.unsupported }
                if audioFormat == nil {
                    var description = AudioStreamBasicDescription(mSampleRate: Double(rates[rateIndex]), mFormatID: kAudioFormatMPEG4AAC,
                        mFormatFlags: UInt32(profile), mBytesPerPacket: 0, mFramesPerPacket: 1_024, mBytesPerFrame: 0,
                        mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
                    // Core Audio expects an MPEG-4 elementary stream descriptor
                    // as the AAC magic cookie, not the two-byte AudioSpecificConfig
                    // alone. A bare ASC lets writing finish but produces an invalid
                    // esds atom whose audio track AVFoundation cannot open.
                    let decoderSpecific: [UInt8] = [0x05, UInt8(cookie.count)] + cookie
                    let decoderPayload: [UInt8] = [0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] + decoderSpecific
                    let decoderDescriptor: [UInt8] = [0x04, UInt8(decoderPayload.count)] + decoderPayload
                    let elementaryPayload: [UInt8] = [0, 1, 0] + decoderDescriptor + [0x06, 1, 2]
                    let magicCookie: [UInt8] = [0x03, UInt8(elementaryPayload.count)] + elementaryPayload
                    let status = magicCookie.withUnsafeBytes { bytes in
                        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
                            layoutSize: 0, layout: nil, magicCookieSize: bytes.count, magicCookie: bytes.baseAddress,
                            extensions: nil, formatDescriptionOut: &audioFormat)
                    }
                    guard status == noErr else { throw Failure.damaged }; audioConfiguration = cookie
                }
                let time = pts + Int64(frame) * 1_024 * 90_000 / Int64(rates[rateIndex])
                audioSamples.append(try store(Data(b[(i + header)..<(i + length)]), pts: time, dts: time,
                                              duration: 1_024 * 90_000 / Int64(rates[rateIndex]), sync: true))
                i += length; frame += 1
            }
        }
    }

    private static func sampleBuffer(_ data: Data, format: CMFormatDescription, pts: Int64,
                                     dts: Int64, duration: Int64, sync: Bool) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: data.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { throw Failure.writing }
        let copied = data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == kCMBlockBufferNoErr else { throw Failure.writing }
        if CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio {
            var packet = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 1_024, mDataByteSize: UInt32(data.count))
            var sample: CMSampleBuffer?
            guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block,
                formatDescription: format, sampleCount: 1, presentationTimeStamp: CMTime(value: pts, timescale: 90_000),
                packetDescriptions: &packet, sampleBufferOut: &sample) == noErr, let sample else { throw Failure.writing }
            return sample
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: duration, timescale: 90_000),
                                       presentationTimeStamp: CMTime(value: pts, timescale: 90_000),
                                       decodeTimeStamp: CMTime(value: dts, timescale: 90_000))
        var size = data.count, sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { throw Failure.writing }
        if !sync, let array = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(array, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
