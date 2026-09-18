//
//  AudioProcessor.swift
//  RandomizerAlarmClock
//
//  Renders a source audio file with a randomized pitch shift and playback speed
//  applied, trimmed to iOS's 30-second alert-sound limit, and writes the result to a
//  .caf file that AlarmKit's AlertConfiguration.AlertSound.named(_:) can play.
//

import Foundation
import AVFoundation
import os

enum AudioProcessorError: Error, LocalizedError {
    case couldNotOpenInput
    case renderSetupFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .couldNotOpenInput: return "Could not open the source audio file."
        case .renderSetupFailed: return "Could not set up offline audio rendering."
        case .renderFailed: return "Rendering the alarm sound failed."
        }
    }
}

struct AudioProcessor {

    static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "audio")

    /// iOS requires alert sounds to be at most 30 seconds; stay comfortably under that.
    /// This is a limit on the *rendered output*, not on the source material.
    static let maxRenderedDuration: Double = 28.0

    /// Picks a random pitch (in cents) and speed (rate multiplier) within an alarm's configured
    /// ranges. Pulled out as a pure function so it's easy to unit test.
    static func randomizedParameters(for alarm: Alarm) -> (pitchCents: Float, rate: Float) {
        let pitch = Float.random(in: min(alarm.pitchMinCents, alarm.pitchMaxCents)...max(alarm.pitchMinCents, alarm.pitchMaxCents))
        let rate = Float.random(in: min(alarm.speedMin, alarm.speedMax)...max(alarm.speedMin, alarm.speedMax))
        return (pitch, rate)
    }

    /// Renders `inputURL` with the given pitch/rate applied and writes a trimmed .caf to `outputURL`.
    /// Runs entirely offline (no audio hardware needed), so it's fast even for a 3-4 minute source file.
    static func renderSound(inputURL: URL, pitchCents: Float, rate: Float, outputURL: URL) throws {
        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: inputURL)
        } catch {
            throw AudioProcessorError.couldNotOpenInput
        }

        let processingFormat = inputFile.processingFormat
        let sampleRate = processingFormat.sampleRate

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitchUnit = AVAudioUnitTimePitch()
        pitchUnit.pitch = pitchCents
        pitchUnit.rate = max(0.25, rate) // AVAudioUnitTimePitch supports roughly 1/32x-32x; alarm ranges stay well inside that.

        engine.attach(player)
        engine.attach(pitchUnit)
        engine.connect(player, to: pitchUnit, format: processingFormat)
        engine.connect(pitchUnit, to: engine.mainMixerNode, format: processingFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: processingFormat)

        do {
            try engine.enableManualRenderingMode(.offline, format: processingFormat, maximumFrameCount: 4096)
        } catch {
            throw AudioProcessorError.renderSetupFailed
        }

        // BUG FIX: this used to trim the *input* to maxRenderedDuration of source frames,
        // ignoring the rate. At the default speedMin of 0.85x, 28s of source stretches to
        // 28 / 0.85 = ~32.9s of output — over iOS's hard 30-second alert-sound
        // limit, at which point iOS discards the custom sound and plays the default one
        // (or nothing, depending on settings). Budget the trim in *output* time instead:
        // outputDuration = inputDuration / rate, so inputDuration = maxRenderedDuration * rate.
        let effectiveRate = Double(pitchUnit.rate)
        let maxInputSeconds = maxRenderedDuration * effectiveRate
        let inputFramesToSchedule = AVAudioFrameCount(min(Double(inputFile.length), maxInputSeconds * sampleRate))

        guard inputFramesToSchedule > 0 else {
            log.error("Input file has no usable audio frames: \(inputURL.lastPathComponent, privacy: .public)")
            throw AudioProcessorError.couldNotOpenInput
        }

        do {
            try engine.start()
        } catch {
            throw AudioProcessorError.renderSetupFailed
        }

        player.scheduleSegment(
            inputFile,
            startingFrame: 0,
            frameCount: inputFramesToSchedule,
            at: nil,
            completionHandler: nil
        )
        player.play()

        // Speed changes tempo without changing duration of *source* frames consumed per unit of
        // output time, so the number of output frames we need is the scheduled input duration
        // divided by rate (a faster rate compresses the same material into less output time).
        // Hard-cap the output as well, so rounding can never push us past the 30s ceiling.
        let targetOutputFrames = AVAudioFrameCount(
            min(Double(inputFramesToSchedule) / effectiveRate, maxRenderedDuration * sampleRate)
        )

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw AudioProcessorError.renderSetupFailed
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: processingFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        var outputFileRef: AVAudioFile?
        do {
            outputFileRef = try AVAudioFile(
                forWriting: outputURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            log.error("Could not open output file \(outputURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AudioProcessorError.renderSetupFailed
        }

        var framesRendered: AVAudioFrameCount = 0
        renderLoop: while framesRendered < targetOutputFrames {
            let framesToPull = min(engine.manualRenderingMaximumFrameCount, targetOutputFrames - framesRendered)
            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(framesToPull, to: renderBuffer)
            } catch {
                throw AudioProcessorError.renderFailed
            }

            switch status {
            case .success:
                do {
                    try outputFileRef?.write(from: renderBuffer)
                } catch {
                    throw AudioProcessorError.renderFailed
                }
                framesRendered += renderBuffer.frameLength
            case .insufficientDataFromInputNode:
                // The player node ran out of scheduled audio before we hit our target
                // (input shorter than expected). Whatever we've written so far is the result.
                break renderLoop
            case .cannotDoInCurrentContext:
                continue renderLoop
            case .error:
                throw AudioProcessorError.renderFailed
            @unknown default:
                throw AudioProcessorError.renderFailed
            }
        }

        player.stop()
        engine.stop()

        // AVAudioFile flushes on deinit; drop the reference before we stat the file so the
        // size check below sees the finished result rather than a partially-written one.
        outputFileRef = nil

        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))
            .flatMap { $0[.size] as? Int } ?? 0
        let renderedSeconds = Double(framesRendered) / sampleRate
        log.info("Rendered \(outputURL.lastPathComponent, privacy: .public): \(renderedSeconds, format: .fixed(precision: 2))s, \(bytes) bytes.")

        guard bytes > 0, framesRendered > 0 else {
            log.error("Render produced an empty file for \(inputURL.lastPathComponent, privacy: .public).")
            throw AudioProcessorError.renderFailed
        }
        guard renderedSeconds <= 30.0 else {
            // Should be impossible given the caps above, but a sound over 30s is silently
            // dropped by iOS, so fail loudly rather than scheduling a dud.
            log.error("Rendered sound is \(renderedSeconds, format: .fixed(precision: 2))s — over the 30s alert-sound limit.")
            throw AudioProcessorError.renderFailed
        }
    }
}
