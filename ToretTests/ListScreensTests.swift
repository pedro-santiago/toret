import CoreLocation
import Foundation
import Testing
import UserNotifications

@testable import Toret

// MARK: - Distance

@Suite("Distance")
struct DistanceTests {
    private let brazil = Locale(identifier: "pt_BR")
    private let america = Locale(identifier: "en_US")

    @Test("Under a kilometre it is whole metres")
    func metres() {
        #expect(Distance.parts(84, locale: brazil).value == "84")
        #expect(Distance.parts(84, locale: brazil).unit == "m")
        #expect(Distance.parts(999, locale: brazil).unit == "m")
        #expect(Distance.parts(0, locale: brazil).value == "0")
    }

    @Test("From a kilometre it is kilometres, with the decimal the device uses")
    func kilometres() {
        #expect(Distance.text(1234, locale: brazil) == "1,2 km")
        #expect(Distance.text(1234, locale: america) == "1.2 km")
        #expect(Distance.text(1000, locale: brazil) == "1 km")
    }

    @Test("Past ten kilometres the decimal is noise")
    func farAway() {
        #expect(Distance.text(12_400, locale: brazil) == "12 km")
    }

    @Test("A negative distance never reaches the screen")
    func negative() {
        #expect(Distance.parts(-5, locale: brazil).value == "0")
    }

    @Test("Spoken distances use the whole word")
    func spoken() {
        #expect(Distance.spoken(84, locale: brazil).contains("metros"))
        #expect(Distance.spoken(2300, locale: brazil).contains("quilômetros"))
    }
}

// MARK: - Perto header

@Suite("Nearby copy")
struct NearbyCopyTests {
    @Test("The count and where it is measured from are both in the sentence")
    func counts() {
        let user = NearbyCopy.headline(within500: 38, nearest: 21, fromUser: true)
        #expect(user.contains("38"))
        #expect(user.contains("de você"))

        let anchored = NearbyCopy.headline(within500: 38, nearest: 21, fromUser: false)
        #expect(anchored.contains("Piazza San Carlo"))
        #expect(!anchored.contains("de você"))
    }

    @Test("One fountain is singular")
    func singular() {
        let one = NearbyCopy.headline(within500: 1, nearest: 40, fromUser: true)
        #expect(one.hasPrefix("1 fonte "))
        #expect(!one.contains("fontes"))
    }

    /// A suburb has nothing within 500 m. An empty list would look like a fault;
    /// the sentence says how far the nearest one is instead.
    @Test("With nothing in reach it says how far the nearest is")
    func nothingInReach() {
        let text = NearbyCopy.headline(within500: 0, nearest: 1800, fromUser: true)
        #expect(text.contains("Nenhuma"))
        #expect(text.contains(Distance.text(1800)))
    }

    @Test("An empty catalogue is said out loud")
    func emptyCatalogue() {
        let text = NearbyCopy.headline(within500: 0, nearest: nil, fromUser: true)
        #expect(text.contains("catálogo"))
    }
}

// MARK: - Location banner

@Suite("Location banner")
struct LocationBannerTests {
    @Test("Nothing to say when the distances are the user's own")
    func silentWhenFine() {
        #expect(LocationBanner.message(for: .live) == nil)
        #expect(LocationBanner.message(for: .asking) == nil)
    }

    @Test("Every other status is spoken")
    func everyStatusSpeaks() {
        let statuses: [LocationStatus] = [
            .searching, .approximate, .denied, .restricted, .outsideTurin(kilometres: 9400),
        ]
        for status in statuses {
            let message = LocationBanner.message(for: status)
            #expect(message != nil)
            #expect(!(message?.text.isEmpty ?? true))
        }
    }

    @Test("Only what the user can fix offers the iOS settings")
    func settingsOnlyWhereUseful() {
        #expect(LocationBanner.message(for: .denied)?.opensSettings == true)
        #expect(LocationBanner.message(for: .approximate)?.opensSettings == true)
        #expect(LocationBanner.message(for: .restricted)?.opensSettings == false)
        #expect(LocationBanner.message(for: .outsideTurin(kilometres: 100))?.opensSettings == false)
        #expect(LocationBanner.message(for: .searching)?.opensSettings == false)
    }

    @Test("A fix far from Turin says how far, and from where it measures instead")
    func outsideTurin() throws {
        let message = try #require(LocationBanner.message(for: .outsideTurin(kilometres: 9400)))
        #expect(message.text.contains("Piazza San Carlo"))
        #expect(message.text.contains("km"))
    }

    @Test("Denied is a warning; being abroad is only worth knowing")
    func tone() {
        #expect(LocationBanner.message(for: .denied)?.tone == .warning)
        #expect(LocationBanner.message(for: .outsideTurin(kilometres: 100))?.tone == .note)
    }
}

// MARK: - Settings

@Suite("Settings copy")
struct SettingsCopyTests {
    @Test("Each location state has its own words")
    func location() {
        let all: [CLAuthorizationStatus] = [
            .authorizedAlways, .authorizedWhenInUse, .denied, .restricted, .notDetermined,
        ]
        let words = all.map(PermissionCopy.location)
        #expect(Set(words).count == all.count)
    }

    @Test("Only the states the user can change themselves offer the settings button")
    func needsSettings() {
        #expect(PermissionCopy.needsSettings(.denied))
        #expect(PermissionCopy.needsSettings(.authorizedWhenInUse))
        #expect(!PermissionCopy.needsSettings(.authorizedAlways))
        #expect(!PermissionCopy.needsSettings(.notDetermined))
    }

    @Test("Notification states, including the one not yet read")
    func notifications() {
        #expect(PermissionCopy.notifications(.authorized) == PermissionCopy.notifications(.provisional))
        #expect(PermissionCopy.notifications(.denied) != PermissionCopy.notifications(.authorized))
        #expect(PermissionCopy.notifications(nil) != PermissionCopy.notifications(.denied))
    }

    @Test("The version comes from the bundle, not from the view")
    func version() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.4", "CFBundleVersion": "202610101200"]
        #expect(AppInfo.versionLine(from: info) == "1.4 (202610101200)")
        #expect(AppInfo.versionLine(from: nil) == "1.0 (1)")
    }
}

// MARK: - Entrance

@Suite("Entrance ledger", .serialized)
@MainActor
struct EntranceLedgerTests {
    /// Tab switches rebuild the screens. The ledger is what keeps the rise from
    /// replaying on every visit.
    @Test("A list plays its entrance once")
    func once() {
        EntranceLedger.reset()
        #expect(!EntranceLedger.hasPlayed("nearby"))
        EntranceLedger.markPlayed("nearby")
        #expect(EntranceLedger.hasPlayed("nearby"))
        #expect(!EntranceLedger.hasPlayed("saved"))
        EntranceLedger.reset()
    }

    @Test("The stagger stays short enough to finish inside half a second")
    func staggerBudget() {
        let last = Double(ScreenMotion.staggerLimit - 1) * ScreenMotion.stagger
        #expect(last + 0.32 < 0.7)
    }
}
