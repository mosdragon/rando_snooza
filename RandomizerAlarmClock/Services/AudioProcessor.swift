//
//  AudioProcessor.swift
//  RandomizerAlarmClock
//
//  Renders a source audio file with a randomized pitch shift and playback speed
//  applied, trimmed to iOS's 30-second notification-sound limit, and writes the
//  result to a .caf file that UNNotificationSound can play.
//

import Foundation
import AVFoundation

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

    /// iOS requires notification sounds to be at most 30 seconds; stay comfortably under that.
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

        // Trim the *input* to maxRenderedDuration worth of source frames before any speed change,
        // so a very long source file doesn't take forever to schedule.
        let inputFramesToSchedule = AVAudioFrameCount(min(Double(inputFile.length), maxRenderedDuration * sampleRate))

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
        let targetOutputFrames = AVAudioFrameCount(Double(inputFramesToSchedule) / Double(pitchUnit.rate))

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

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
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
                    try outputFile.write(from: renderBuffer)
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
    }
}
