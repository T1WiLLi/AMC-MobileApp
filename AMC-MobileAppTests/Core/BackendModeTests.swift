import Testing
@testable import AMC_MobileApp

/// Choix du backend au lancement (B-013) : logique pure, sans réseau ni Firebase.
struct BackendModeTests {
    // MARK: - Résolution du mode

    private func resolve(
        sdk: Bool = true, plist: Bool = true, _ options: BackendLaunchOptions = .init(), debug: Bool = true
    ) -> BackendMode {
        BackendMode.resolve(sdkAvailable: sdk, hasConfigFile: plist, options: options, isDebugBuild: debug)
    }

    @Test func withoutSDKAlwaysFake() {
        let all = BackendLaunchOptions(useFakeBackend: true, useFirebaseEmulator: true)
        for options in [BackendLaunchOptions(), BackendLaunchOptions(useFirebaseEmulator: true), all] {
            for debug in [true, false] {
                #expect(resolve(sdk: false, options, debug: debug) == .fake)
            }
        }
    }

    @Test func withoutPlistFakeUnlessEmulator() {
        #expect(resolve(plist: false) == .fake)
        #expect(resolve(plist: false, debug: false) == .fake)
        // Le projet demo-grenier de l'émulateur n'a pas besoin du plist.
        #expect(resolve(plist: false, BackendLaunchOptions(useFirebaseEmulator: true)) == .emulator)
    }

    @Test func defaultsToDemoProject() {
        #expect(resolve() == .demoProject)
    }

    @Test func emulatorFlagSelectsEmulator() {
        #expect(resolve(BackendLaunchOptions(useFirebaseEmulator: true)) == .emulator)
    }

    @Test func fakeFlagWinsOverEmulator() {
        #expect(resolve(BackendLaunchOptions(useFakeBackend: true, useFirebaseEmulator: true)) == .fake)
    }

    @Test func releaseUsesDemoProjectUnlessExplicitFlag() {
        // T-127 : en Release aussi, le plist mène au vrai projet de démo ; un argument explicite reste honoré.
        #expect(resolve(debug: false) == .demoProject)
        #expect(resolve(BackendLaunchOptions(useFakeBackend: true), debug: false) == .fake)
        #expect(resolve(BackendLaunchOptions(useFirebaseEmulator: true), debug: false) == .emulator)
        #expect(resolve(plist: false, debug: false) == .fake)
    }

    @Test func unitTestsAlwaysFake() {
        let options = BackendLaunchOptions(useFirebaseEmulator: true, isRunningTests: true)
        for debug in [true, false] {
            #expect(resolve(options, debug: debug) == .fake)
            #expect(resolve(BackendLaunchOptions(isRunningTests: true), debug: debug) == .fake)
        }
    }

    @Test func detectsXCTestHost() {
        let environment = ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]
        #expect(BackendLaunchOptions(arguments: ["app"], environment: environment).isRunningTests)
        #expect(!BackendLaunchOptions(arguments: ["app"], environment: [:]).isRunningTests)
    }

    @Test func shortAliases() {
        #expect(BackendLaunchOptions(arguments: ["app", "-useFakeData"], environment: [:]).useFakeBackend)
        #expect(BackendLaunchOptions(arguments: ["app", "-useEmulator", "YES"], environment: [:]).useFirebaseEmulator)
        #expect(!BackendLaunchOptions(arguments: ["app", "-useEmulator", "NO"], environment: [:]).useFirebaseEmulator)
    }

    @Test func onlyFakeSkipsFirebase() {
        #expect(!BackendMode.fake.usesFirebase)
        #expect(BackendMode.emulator.usesFirebase)
        #expect(BackendMode.demoProject.usesFirebase)
    }

    // MARK: - Lecture des arguments et de l'environnement

    @Test(arguments: [
        (["-useFirebaseEmulator", "YES"], true),
        (["-useFirebaseEmulator", "1"], true),
        (["-useFirebaseEmulator", "true"], true),
        (["-useFirebaseEmulator"], true),
        (["-useFirebaseEmulator", "-useFakeBackend", "NO"], true),
        (["-useFirebaseEmulator", "NO"], false),
        (["-useFirebaseEmulator", "0"], false),
        (["-NSDoubleLocalizedStrings", "YES"], false),
        ([], false),
    ])
    func parsesEmulatorArgument(arguments: [String], expected: Bool) {
        let options = BackendLaunchOptions(arguments: ["/path/AMC-MobileApp"] + arguments, environment: [:])
        #expect(options.useFirebaseEmulator == expected)
    }

    @Test func parsesFakeBackendArgument() {
        let options = BackendLaunchOptions(arguments: ["app", "-useFakeBackend", "YES"], environment: [:])
        #expect(options.useFakeBackend)
        #expect(!options.useFirebaseEmulator)
    }

    @Test func readsEnvironmentVariables() {
        let options = BackendLaunchOptions(
            arguments: ["app"],
            environment: ["USE_FIREBASE_EMULATOR": "1", "USE_FAKE_BACKEND": "YES", "FIREBASE_EMULATOR_HOST": "192.168.1.20"]
        )
        #expect(options.useFirebaseEmulator)
        #expect(options.useFakeBackend)
        #expect(options.emulator.host == "192.168.1.20")
    }

    @Test func argumentOverridesEnvironment() {
        let options = BackendLaunchOptions(
            arguments: ["app", "-useFirebaseEmulator", "NO", "-firebaseEmulatorHost", "10.0.0.5"],
            environment: ["USE_FIREBASE_EMULATOR": "1", "FIREBASE_EMULATOR_HOST": "192.168.1.20"]
        )
        #expect(!options.useFirebaseEmulator)
        #expect(options.emulator.host == "10.0.0.5")
    }

    @Test func emulatorDefaultsMatchFirebaseJSON() {
        let config = BackendLaunchOptions(arguments: [], environment: [:]).emulator
        #expect(config == FirebaseEmulatorConfig(
            projectID: "demo-grenier", host: "127.0.0.1", authPort: 9099, firestorePort: 8080, storagePort: 9199
        ))
    }

    // MARK: - Fabriques de dépôts

    @Test func liveRepositoriesForEveryMode() async throws {
        // Fake : les données de démo en mémoire.
        #expect(!(try await AppRepositories.live(mode: .fake).pickupPoints.pickupPoints()).isEmpty)
        // Firebase sans FirebaseApp configurée (tests) : dépôts vides, jamais les personas de FakeData (T-127).
        for mode in [BackendMode.emulator, .demoProject] {
            let repos = AppRepositories.live(mode: mode)
            #expect(try await repos.pickupPoints.pickupPoints().isEmpty)
            #expect(try await repos.vendors.vendors().isEmpty)
        }
    }
}
