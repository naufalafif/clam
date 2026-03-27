import Testing
import Foundation
@testable import ClamLib

@Suite("RateLimit")
struct RateLimitTests {

    // MARK: - percentage

    @Test("percentage converts 0.0 to 0")
    func percentageZero() {
        #expect(RateLimit(utilization: 0.0, resetsAt: nil).percentage == 0)
    }

    @Test("percentage converts 0.5 to 50")
    func percentageHalf() {
        #expect(RateLimit(utilization: 0.5, resetsAt: nil).percentage == 50)
    }

    @Test("percentage converts 1.0 to 100")
    func percentageFull() {
        #expect(RateLimit(utilization: 1.0, resetsAt: nil).percentage == 100)
    }

    @Test("percentage rounds 0.456 to 46")
    func percentageRounding() {
        #expect(RateLimit(utilization: 0.456, resetsAt: nil).percentage == 46)
    }

    @Test("percentage rounds 0.999 to 100")
    func percentageNearFull() {
        #expect(RateLimit(utilization: 0.999, resetsAt: nil).percentage == 100)
    }

    // MARK: - color

    @Test("color is green below 0.4")
    func colorGreen() {
        #expect(RateLimit(utilization: 0.0, resetsAt: nil).color == .green)
        #expect(RateLimit(utilization: 0.39, resetsAt: nil).color == .green)
    }

    @Test("color is yellow from 0.4 to 0.7")
    func colorYellow() {
        #expect(RateLimit(utilization: 0.4, resetsAt: nil).color == .yellow)
        #expect(RateLimit(utilization: 0.69, resetsAt: nil).color == .yellow)
    }

    @Test("color is red at 0.7 and above")
    func colorRed() {
        #expect(RateLimit(utilization: 0.7, resetsAt: nil).color == .red)
        #expect(RateLimit(utilization: 1.0, resetsAt: nil).color == .red)
    }

    // MARK: - resetLabel

    @Test("resetLabel returns ? for nil date")
    func resetLabelNil() {
        #expect(RateLimit(utilization: 0, resetsAt: nil).resetLabel == "?")
    }

    @Test("resetLabel formats time for same-day reset")
    func resetLabelSameDay() {
        let future = Date().addingTimeInterval(7200) // 2 hours from now
        let label = RateLimit(utilization: 0.5, resetsAt: future).resetLabel
        #expect(label.hasPrefix("@"))
        // "h a" format produces strings like "3 pm"
        let timePart = String(label.dropFirst())
        #expect(timePart.contains(" "))
    }

    @Test("resetLabel formats day for next-day reset")
    func resetLabelNextDay() {
        let future = Date().addingTimeInterval(172_800) // 2 days from now
        let label = RateLimit(utilization: 0.5, resetsAt: future).resetLabel
        #expect(label.hasPrefix("@"))
        // "EEE" format produces abbreviated weekday like "mon", "tue"
        let dayPart = String(label.dropFirst())
        #expect(!dayPart.isEmpty)
    }

    // MARK: - empty

    @Test("empty has zero utilization and nil date")
    func empty() {
        let e = RateLimit.empty
        #expect(e.utilization == 0)
        #expect(e.resetsAt == nil)
        #expect(e.percentage == 0)
        #expect(e.color == .green)
        #expect(e.resetLabel == "?")
    }
}
