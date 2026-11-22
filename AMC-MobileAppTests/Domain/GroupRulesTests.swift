import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de GroupRules (E03 : RQ-025, RQ-026, RQ-028, RQ-030).
struct GroupRulesTests {
    /// Générateur déterministe (SplitMix64) pour des codes reproductibles.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let now = Date(timeIntervalSince1970: 1_795_000_000)
    static let draft = GroupRules.Draft(
        name: "  Voisins   de Parc-Ex ", neighborhood: " Parc-Extension ", centerGeohash: "f25eh8",
        radiusMeters: 1_500, isPublic: false
    )

    static func member(_ id: String, _ role: GroupMember.Role = .member) -> GroupMember {
        GroupMember(householdId: id, role: role, joinedAt: now)
    }

    static func invalidMessage(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let AppError.invalidInput(message) { return message } catch { return "autre: \(error)" }
    }

    // MARK: RQ-025 Création

    @Test func makeGroupBuildsTheGroupWithTheCreatorAsCoordinator() throws {
        let creation = try GroupRules.makeGroup(
            from: Self.draft, creatorUserId: "user-jean", creatorHouseholdId: "hh-jean", now: Self.now,
            makeId: { "group-1" }, makeInviteCode: { "ABC234" }
        )
        let group = creation.group
        #expect(group.id == "group-1")
        #expect(group.name == "Voisins de Parc-Ex")
        #expect(group.neighborhood == "parc-extension")
        #expect(group.centerGeohash == "f25eh8")
        #expect(group.radiusMeters == 1_500)
        #expect(group.coordinatorIds == ["user-jean"])
        #expect(group.householdCount == 1)
        #expect(!group.isPublic)
        #expect(group.inviteCode == "ABC234")
        #expect(creation.creatorMember == GroupMember(householdId: "hh-jean", role: .coordinator, joinedAt: Self.now, userId: "user-jean"))
    }

    @Test func makeGroupDefaultCodeIsValid() throws {
        let creation = try GroupRules.makeGroup(from: Self.draft, creatorUserId: "u", creatorHouseholdId: "h")
        #expect(GroupRules.isValidInviteCode(creation.group.inviteCode))
        #expect(!creation.group.id.isEmpty)
    }

    @Test(arguments: [("ab", false), ("abc", true), (String(repeating: "a", count: 40), true), (String(repeating: "a", count: 41), false), ("  a  b  ", true), (" a ", false)])
    func nameLength(name: String, valid: Bool) {
        var draft = Self.draft
        draft.name = name
        #expect((Self.invalidMessage { try GroupRules.validate(draft) } == nil) == valid)
    }

    @Test(arguments: [(999, false), (1_000, true), (2_000, true), (2_001, false)])
    func radiusBounds(radius: Int, valid: Bool) {
        var draft = Self.draft
        draft.radiusMeters = radius
        #expect((Self.invalidMessage { try GroupRules.validate(draft) } == nil) == valid)
    }

    @Test func emptyNeighborhoodIsRejectedWithAFrenchMessage() {
        var draft = Self.draft
        draft.neighborhood = "   "
        #expect(Self.invalidMessage { try GroupRules.validate(draft) } == "Choisis le quartier de ton groupe.")
    }

    @Test func emptyGeohashIsRejected() {
        var draft = Self.draft
        draft.centerGeohash = ""
        #expect(Self.invalidMessage { try GroupRules.validate(draft) } != nil)
    }

    // MARK: RQ-026 Invitation

    @Test func generatedCodesUseTheUnambiguousAlphabet() {
        var rng = SeededGenerator(state: 42)
        for _ in 0..<200 {
            let code = GroupRules.generateInviteCode(using: &rng)
            #expect(code.count == GroupRules.inviteCodeLength)
            #expect(code.allSatisfy { GroupRules.inviteAlphabet.contains($0) })
            #expect(!code.contains { "01OI".contains($0) })
            #expect(GroupRules.isValidInviteCode(code))
        }
    }

    @Test func generationIsDeterministicWithASeed() {
        var a = SeededGenerator(state: 7)
        var b = SeededGenerator(state: 7)
        #expect(GroupRules.generateInviteCode(using: &a) == GroupRules.generateInviteCode(using: &b))
    }

    @Test func generationAvoidsExistingCodes() {
        var probe = SeededGenerator(state: 3)
        let first = GroupRules.generateInviteCode(using: &probe)
        var rng = SeededGenerator(state: 3)
        let code = GroupRules.generateInviteCode(avoiding: [first.lowercased()], using: &rng)
        #expect(code != first)
    }

    @Test func normalisationAndValidation() throws {
        #expect(GroupRules.normalizedInviteCode(" pa-rex 1 ") == "PAREX1")
        #expect(try GroupRules.validatedInviteCode("parex1") == "PAREX1")
        #expect(GroupRules.isValidInviteCode("PAREX1"))
        #expect(!GroupRules.isValidInviteCode("PAREX"))
        #expect(!GroupRules.isValidInviteCode("PAREX12"))
        #expect(!GroupRules.isValidInviteCode("PARÉX1"))
        #expect(Self.invalidMessage { _ = try GroupRules.validatedInviteCode("abc") } != nil)
    }

    @Test func fixtureCodesStayValid() {
        for code in ["PAREX1", "ROSEM1", "HOCHE1", "STMIC1", "VERDU1", "CDNEI1", "MTLNO1", "VILLE1"] {
            #expect(GroupRules.isValidInviteCode(code))
        }
    }

    @Test func linksRoundTrip() throws {
        let app = try #require(GroupRules.appInviteLink(for: "abc234"))
        let web = try #require(GroupRules.shareableInviteLink(for: "ABC234"))
        #expect(app.absoluteString == "grenier://join/ABC234")
        #expect(web.absoluteString == "https://grenier.app/join/ABC234")
        #expect(GroupRules.inviteCode(from: app) == "ABC234")
        #expect(GroupRules.inviteCode(from: web) == "ABC234")
        #expect(GroupRules.appInviteLink(for: "x") == nil)
    }

    @Test(arguments: [
        "https://evil.app/join/ABC234",
        "https://grenier.app.evil.com/join/ABC234",
        "http://grenier.app/join/ABC234",
        "https://grenier.app/invite/ABC234",
        "https://grenier.app/join/ABC234/extra",
        "https://grenier.app/join/",
        "grenier://open/ABC234",
        "grenier://join/ABC234/x",
        "grenier://join/AB",
        "other://join/ABC234",
    ])
    func parsingRejectsOtherLinks(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(GroupRules.inviteCode(from: url) == nil)
    }

    @Test func parsingAcceptsLowercaseCodesAndQueries() throws {
        #expect(GroupRules.inviteCode(from: try #require(URL(string: "https://GRENIER.app/join/abc234?ref=sms"))) == "ABC234")
    }

    @Test func userInputAcceptsACodeOrALink() {
        #expect(GroupRules.inviteCode(fromUserInput: " abc-234 ") == "ABC234")
        #expect(GroupRules.inviteCode(fromUserInput: "https://grenier.app/join/ABC234") == "ABC234")
        #expect(GroupRules.inviteCode(fromUserInput: "https://evil.app/join/ABC234") == nil)
        #expect(GroupRules.inviteCode(fromUserInput: "bonjour") == nil)
    }

    // MARK: RQ-030 Limite de 3 groupes

    @Test func canJoinUpToThreeGroups() {
        #expect(GroupRules.canJoin(householdGroupIds: [], groupId: "g1"))
        #expect(GroupRules.canJoin(householdGroupIds: ["g1", "g2"], groupId: "g3"))
        #expect(!GroupRules.canJoin(householdGroupIds: ["g1", "g2", "g3"], groupId: "g4"))
        #expect(GroupRules.canJoin(householdGroupIds: ["g1", "g2", "g3"], groupId: "g2"))
    }

    @Test func joiningAppendsOrIsANoOp() throws {
        #expect(try GroupRules.joining(householdGroupIds: ["g1"], groupId: "g2") == ["g1", "g2"])
        #expect(try GroupRules.joining(householdGroupIds: ["g1", "g2", "g3"], groupId: "g3") == ["g1", "g2", "g3"])
    }

    @Test func joiningAFourthGroupThrows() {
        let message = Self.invalidMessage { _ = try GroupRules.joining(householdGroupIds: ["g1", "g2", "g3"], groupId: "g4") }
        #expect(message?.contains("3 groupes") == true)
    }

    // MARK: RQ-028 Coordonnateurs

    static let members = [member("a", .coordinator), member("b"), member("c")]

    @Test func coordinatorCanAppointAndDemote() throws {
        let appointed = try GroupRules.appointingCoordinator("b", by: "a", in: Self.members)
        #expect(GroupRules.isCoordinator("b", in: appointed))
        let demoted = try GroupRules.removingCoordinator("a", by: "b", in: appointed)
        #expect(!GroupRules.isCoordinator("a", in: demoted))
        #expect(demoted.count == 3)
    }

    @Test func memberCannotManageRoles() {
        #expect(throws: AppError.permissionDenied) { try GroupRules.appointingCoordinator("c", by: "b", in: Self.members) }
        #expect(throws: AppError.permissionDenied) { try GroupRules.removingCoordinator("a", by: "b", in: Self.members) }
        #expect(throws: AppError.permissionDenied) { try GroupRules.removingMember("c", by: "b", in: Self.members) }
    }

    @Test func unknownTargetIsNotFound() {
        #expect(throws: AppError.notFound) { try GroupRules.appointingCoordinator("z", by: "a", in: Self.members) }
        #expect(throws: AppError.notFound) { try GroupRules.removingMember("z", by: "a", in: Self.members) }
    }

    @Test func lastCoordinatorMustStay() {
        #expect(Self.invalidMessage { _ = try GroupRules.removingCoordinator("a", by: "a", in: Self.members) }?.contains("au moins un coordonnateur") == true)
        #expect(Self.invalidMessage { _ = try GroupRules.removingMember("a", by: "a", in: Self.members) } != nil)
    }

    @Test func coordinatorRemovesAMemberAndMemberCanLeave() throws {
        #expect(try GroupRules.removingMember("b", by: "a", in: Self.members).map(\.householdId) == ["a", "c"])
        #expect(try GroupRules.removingMember("c", by: "c", in: Self.members).map(\.householdId) == ["a", "b"])
    }

    @Test func coordinatorCanLeaveWhenAnotherRemains() throws {
        let two = try GroupRules.appointingCoordinator("b", by: "a", in: Self.members)
        #expect(try GroupRules.removingMember("a", by: "a", in: two).map(\.householdId) == ["b", "c"])
    }

    @Test func demotingAPlainMemberIsANoOp() throws {
        #expect(try GroupRules.removingCoordinator("b", by: "a", in: Self.members) == Self.members)
    }

    @Test func coordinatorIdsOnTheGroup() throws {
        let group = try GroupRules.makeGroup(from: Self.draft, creatorUserId: "u1", creatorHouseholdId: "h1",
                                             makeId: { "g" }, makeInviteCode: { "ABC234" }).group
        #expect(throws: AppError.permissionDenied) { try GroupRules.appointingCoordinator("u2", by: "u9", in: group) }
        let two = try GroupRules.appointingCoordinator("u2", by: "u1", in: group)
        #expect(two.coordinatorIds == ["u1", "u2"])
        #expect(try GroupRules.appointingCoordinator("u2", by: "u1", in: two) == two)
        #expect(try GroupRules.removingCoordinator("u1", by: "u1", in: two).coordinatorIds == ["u2"])
        #expect(Self.invalidMessage { _ = try GroupRules.removingCoordinator("u1", by: "u1", in: group) } != nil)
    }
}
