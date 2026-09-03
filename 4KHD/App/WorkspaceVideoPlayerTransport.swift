import AVFoundation
import Foundation

nonisolated enum WorkspaceVideoPlayerTransport {
    static let skipSteps: [TimeInterval] = [5, 10, 30, 60, 300]
    static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    static let keyboardSkipSeconds: TimeInterval = 10
    static let defaultRate: Float = 1
    static let defaultVolume: Float = 1
    static let rateDefaultsKey = "com.songziqiang.4khd.videoPlayerRate.v1"
    static let volumeDefaultsKey = "com.songziqiang.4khd.videoPlayerVolume.v1"

    static func skipLabel(for seconds: TimeInterval, direction: Int) -> String {
        let magnitude: String
        if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 {
            magnitude = "\(Int(seconds / 60))m"
        } else {
            magnitude = "\(Int(seconds))s"
        }
        return direction < 0 ? "-\(magnitude)" : "+\(magnitude)"
    }

    static func rateLabel(_ rate: Float) -> String {
        if rate == rate.rounded() {
            return "\(Int(rate))×"
        }
        return String(format: "%g×", rate)
    }

    static func nearestRate(_ rate: Float) -> Float {
        rates.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? defaultRate
    }

    static func rateIndex(_ rate: Float) -> Int {
        rates.firstIndex(of: nearestRate(rate)) ?? rates.firstIndex(of: defaultRate) ?? 0
    }

    static func clampedTime(
        current: TimeInterval,
        delta: TimeInterval,
        duration: TimeInterval?
    ) -> TimeInterval {
        let next = current + delta
        if let duration, duration.isFinite, duration >= 0 {
            return min(max(next, 0), duration)
        }
        return max(next, 0)
    }

    static func durationSeconds(from time: CMTime) -> TimeInterval? {
        guard time.isValid, time.isNumeric, !time.isIndefinite else { return nil }
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    static func durationSeconds(from item: AVPlayerItem) -> TimeInterval? {
        if let duration = durationSeconds(from: item.duration) {
            return duration
        }
        guard let range = item.seekableTimeRanges.last?.timeRangeValue else { return nil }
        return durationSeconds(from: range.end)
    }

    static func formatClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    static func storedRate(defaults: UserDefaults = .standard) -> Float {
        guard defaults.object(forKey: rateDefaultsKey) != nil else { return defaultRate }
        return nearestRate(defaults.float(forKey: rateDefaultsKey))
    }

    static func storeRate(_ rate: Float, defaults: UserDefaults = .standard) {
        defaults.set(nearestRate(rate), forKey: rateDefaultsKey)
    }

    static func storedVolume(defaults: UserDefaults = .standard) -> Float {
        guard defaults.object(forKey: volumeDefaultsKey) != nil else { return defaultVolume }
        return min(max(defaults.float(forKey: volumeDefaultsKey), 0), 1)
    }

    static func storeVolume(_ volume: Float, defaults: UserDefaults = .standard) {
        defaults.set(min(max(volume, 0), 1), forKey: volumeDefaultsKey)
    }
}
