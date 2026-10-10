import Foundation
import Testing

@testable import Toret

@Suite("Detail screen")
@MainActor
struct DetailTests {
    @Test("Metres stay metres until they stop being useful")
    func distanceUnits() {
        #expect(DetailScreen.distanceParts(84) == ("84", "m"))
        #expect(DetailScreen.distanceParts(999) == ("999", "m"))
        let far = DetailScreen.distanceParts(2430)
        #expect(far.unit == "km")
        #expect(far.value == "2,4")
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func summary(_ state: WaterState, hoursAgo: Double?) -> CommunitySummary {
        CommunitySummary(
            state: state,
            latestDate: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
            average: nil, ratingCount: 0, reportCount: hoursAgo == nil ? 0 : 1
        )
    }

    /// A state with no age behind it is a rumour, so the sentence always carries
    /// how old the report is.
    @Test("A reported state always says how old the report is")
    func sentenceCarriesAge() {
        let running = summary(.running, hoursAgo: 2).sentence(now: now)
        #expect(running.hasPrefix("Água corrente"))
        #expect(running.contains("relato"))
        #expect(running.contains("2"))
    }

    @Test("Nobody having reported is said plainly")
    func sentenceWithoutReports() {
        #expect(summary(.unknown, hoursAgo: nil).sentence(now: now) == "Sem relato recente")
    }

    @Test("A stale report is called stale, not repeated as fact")
    func sentenceStale() {
        let text = summary(.unknown, hoursAgo: 100).sentence(now: now)
        #expect(text.hasPrefix("Sem relato recente"))
        #expect(text.contains("Último relato"))
        #expect(!text.contains("Água corrente"))
    }

    @Test("Titles break at the most balanced word boundary")
    func balancedTitles() {
        #expect(DetailTitle.balancedLines("Superga") == ["Superga"])
        #expect(DetailTitle.balancedLines("Via Po") == ["Via", "Po"])
        let long = DetailTitle.balancedLines("Corso Vittorio Emanuele II")
        #expect(long.count == 2)
        #expect(long.joined(separator: " ") == "Corso Vittorio Emanuele II")
        // Neither line is the whole name, and the shorter is not a lone "II".
        #expect(long[1] != "II")
    }

    @Test("A name of three words is split, not left on one line")
    func threeWords() {
        let lines = DetailTitle.balancedLines("Piazza Vittorio Veneto")
        #expect(lines.count == 2)
        #expect(lines.joined(separator: " ") == "Piazza Vittorio Veneto")
    }
}
