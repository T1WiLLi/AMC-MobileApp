import CoreImage
import Foundation
import Testing
@testable import AMC_MobileApp

struct QRMatrixTests {
    @Test func emptyPayloadHasNoCode() {
        #expect(QRMatrix("") == nil)
    }

    @Test func versionOneSizeAndFinderPatterns() throws {
        let matrix = try #require(QRMatrix("GRN-4821", correction: .low))
        #expect(matrix.size == 21)
        #expect(matrix.modules.count == 21 * 21)
        // Les trois motifs de repérage : coins foncés, anneau clair, centre foncé.
        for (row, column) in [(0, 0), (0, 14), (14, 0)] {
            #expect(matrix[row, column])
            #expect(matrix[row + 6, column + 6])
            #expect(!matrix[row + 1, column + 1])
            #expect(matrix[row + 3, column + 3])
        }
    }

    @Test func longerPayloadGrowsTheCode() throws {
        let short = try #require(QRMatrix("GRN"))
        let long = try #require(QRMatrix(String(repeating: "grenier://part/GRN-4821/", count: 4)))
        #expect(long.size > short.size)
        #expect((long.size - 21) % 4 == 0)
    }

    @Test func deterministic() {
        #expect(QRMatrix("grenier://part/GRN-4821") == QRMatrix("grenier://part/GRN-4821"))
        #expect(QRMatrix("grenier://part/GRN-4821") != QRMatrix("grenier://part/GRN-4822"))
    }

    @Test func outOfBoundsIsLight() throws {
        let matrix = try #require(QRMatrix("GRN"))
        #expect(!matrix[-1, 0])
        #expect(!matrix[0, matrix.size])
    }

    @Test(arguments: ["grenier://part/GRN-4821", "grenier://rejoindre?code=PARCEX", "Montréal −19 %"])
    func renderedImageDecodesBackToPayload(payload: String) throws {
        let matrix = try #require(QRMatrix(payload))
        let image = try #require(matrix.cgImage(scale: 10))
        #expect(image.width == (matrix.size + 2 * QRMatrix.quietZone) * 10)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }
        #expect(features.first?.messageString == payload)
    }
}

struct PickupScheduleTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal")!
        return calendar
    }()

    var slot: PickupSlot {
        let start = calendar.date(from: DateComponents(year: 2025, month: 11, day: 27, hour: 17))!
        return PickupSlot(start: start, end: start.addingTimeInterval(90 * 60))
    }

    @Test func slotTextMatchesMockup() {
        #expect(PickupSchedule.slotText(slot, calendar: calendar) == "Jeudi 27 novembre · 17 h – 18 h 30")
    }

    @Test func timeText() {
        #expect(PickupSchedule.timeText(slot.start, calendar: calendar) == "17 h")
        #expect(PickupSchedule.timeText(slot.start.addingTimeInterval(5 * 60), calendar: calendar) == "17 h 05")
    }

    @Test func countdownBeforeSlot() {
        let text = { (minutes: Double) in
            PickupSchedule.countdownText(now: slot.start.addingTimeInterval(-minutes * 60), slot: slot, calendar: calendar)
        }
        #expect(text(25) == "Cueillette dans 25 min")
        #expect(text(24.5) == "Cueillette dans 25 min")
        #expect(text(0.2) == "Cueillette dans 1 min")
        #expect(text(60) == "Cueillette dans 1 h")
        #expect(text(135) == "Cueillette dans 2 h 15")
        #expect(text(24 * 60) == "Cueillette dans 1 jour")
        #expect(text(3 * 24 * 60 + 30) == "Cueillette dans 3 jours")
    }

    @Test func countdownDuringAndAfterSlot() {
        let during = slot.start.addingTimeInterval(10 * 60)
        #expect(PickupSchedule.state(now: during, slot: slot) == .ongoing)
        #expect(PickupSchedule.countdownText(now: during, slot: slot, calendar: calendar) == "Cueillette en cours jusqu'à 18 h 30")
        #expect(PickupSchedule.state(now: slot.end, slot: slot) == .finished)
        #expect(PickupSchedule.countdownText(now: slot.end, slot: slot, calendar: calendar) == "Créneau terminé")
    }

    @Test func directionsOpenPlansOnFoot() throws {
        let url = try #require(PickupSchedule.directionsURL(to: "7420 rue Ogilvy, Montréal"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "maps.apple.com")
        #expect(components.queryItems?.first { $0.name == "daddr" }?.value == "7420 rue Ogilvy, Montréal")
        #expect(components.queryItems?.first { $0.name == "dirflg" }?.value == "w")
        #expect(PickupSchedule.directionsURL(to: "") == nil)
    }
}

@MainActor
struct PickupQRCardTests {
    func share(code: String?) -> Share {
        Share(householdId: "household-amina", quantity: 1, finalPriceCents: nil, isPaid: false,
              suspendedAmountCents: 0, subsidyCents: 0, qrCode: code, isPickedUp: false)
    }

    @Test func payloadUsesShareCode() {
        #expect(PickupQRCard.qrPayload(for: share(code: "grenier://part/GRN-4821")) == "grenier://part/GRN-4821")
    }

    @Test func payloadFallsBackToHousehold() {
        #expect(PickupQRCard.qrPayload(for: share(code: nil)) == "grenier://part/household-amina")
        #expect(PickupQRCard.qrPayload(for: share(code: "")) == "grenier://part/household-amina")
    }
}

@MainActor
struct InviteCardTests {
    @Test func shareMessageMatchesSpec() {
        let message = InviteCard.shareMessage(groupName: "Parc-Ex Ouest", inviteCode: "PARCEX", missingFamilies: 1, discountPercent: 19)
        #expect(message == "Rejoins Parc-Ex Ouest sur LeGrenier : il manque 1 famille pour débloquer −19 %. Code d'invitation : PARCEX")
    }

    @Test func urgencyLinePlural() {
        #expect(InviteCard.urgencyLine(missingFamilies: 3, discountPercent: 19) == "il manque 3 familles pour débloquer −19 %")
        #expect(InviteCard.urgencyLine(missingFamilies: 2, discountPercent: nil) == "il manque 2 familles pour le prochain palier")
        #expect(InviteCard.urgencyLine(missingFamilies: 0, discountPercent: 19) == nil)
        #expect(InviteCard.urgencyLine(missingFamilies: nil, discountPercent: 19) == nil)
    }

    @Test func shareMessageWithoutTier() {
        let message = InviteCard.shareMessage(groupName: "Parc-Ex Ouest", inviteCode: "PARCEX", missingFamilies: nil, discountPercent: nil)
        #expect(message.hasPrefix("Rejoins Parc-Ex Ouest sur LeGrenier : on achète en gros"))
        #expect(message.hasSuffix("Code d'invitation : PARCEX"))
    }

    @Test func inviteURLCarriesCode() throws {
        let url = InviteCard.inviteURL(for: CardPreviewData.group)
        #expect(url.absoluteString == "grenier://join/PARCEX")
        #expect(GroupRules.inviteCode(from: url) == "PARCEX")
        let matrix = try #require(QRMatrix(url.absoluteString))
        #expect(matrix.size >= 21)
    }
}
