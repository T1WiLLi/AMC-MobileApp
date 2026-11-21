import SwiftUI

/// Format d'affichage d'un `AnimatedCounter`.
enum CounterFormat: Sendable, Hashable {
    /// Valeur en cents : « 48 $ », « 3 900 $ ».
    case money
    /// Entier, avec unité facultative : « 12 », « 310 kg ».
    case integer(unit: String? = nil)
    /// Décimal, avec unité : « 1,2 t ».
    case decimal(unit: String, fractionDigits: Int = 1)
    /// Fraction de 0 à 1 : « 62 % ».
    case percent
    /// Réduction : « −41 km ».
    case reduction(unit: String)

    func string(for value: Double) -> String {
        let nbsp = ImpactFormat.nbsp
        switch self {
        case .money:
            return Money.formatRounded(Cents(value.rounded()))
        case .integer(let unit):
            let number = ImpactFormat.integer(Int(value.rounded()))
            return unit.map { "\(number)\(nbsp)\($0)" } ?? number
        case .decimal(let unit, let digits):
            return "\(ImpactFormat.decimal(value, fractionDigits: digits))\(nbsp)\(unit)"
        case .percent:
            return String(localized: "\(ImpactFormat.integer(Int((value * 100).rounded())))\(nbsp)%")
        case .reduction(let unit):
            let number = ImpactFormat.integer(Int(value.rounded()))
            return value.rounded() == 0 ? "0\(nbsp)\(unit)" : "−\(number)\(nbsp)\(unit)"
        }
    }

    /// Version lue par VoiceOver (« moins 41 km » plutôt que le signe typographique).
    func accessibilityString(for value: Double) -> String {
        switch self {
        case .reduction(let unit):
            String(localized: "\(ImpactFormat.integer(Int(value.rounded()))) \(unit) en moins")
        default:
            string(for: value)
        }
    }
}

extension EnvironmentValues {
    /// Les compteurs et graphiques de l'écran Impact montent-ils à l'apparition ? (`false` pour les captures.)
    @Entry var impactAnimatesOnAppear = true
}

/// Compteur qui monte de 0 à sa valeur à l'apparition, chiffres en `.numericText()`.
/// Statique sous Reduce Motion. Le style (police, couleur) vient de l'appelant.
///
///     AnimatedCounter(value: 4800, format: .money)
///         .priceStyle(.largeTitle.bold())
///         .foregroundStyle(.economie)
struct AnimatedCounter: View {
    let value: Double
    var format: CounterFormat = .integer()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.impactAnimatesOnAppear) private var animatesOnAppear
    @State private var shown: Double?

    init(value: Double, format: CounterFormat = .integer()) {
        self.value = value
        self.format = format
    }

    init(value: Int, format: CounterFormat = .integer()) {
        self.init(value: Double(value), format: format)
    }

    private var isStatic: Bool { reduceMotion || !animatesOnAppear }

    /// Valeur affichée : la cible si statique, sinon 0 jusqu'à l'apparition.
    private var displayed: Double { isStatic ? value : (shown ?? 0) }

    var body: some View {
        Text(format.string(for: displayed))
            .monospacedDigit()
            .contentTransition(isStatic ? .identity : .numericText(value: displayed))
            .accessibilityLabel(format.accessibilityString(for: value))
            .task(id: value) {
                guard !isStatic else { return }
                if shown == nil {
                    // Laisse la vue apparaître à 0 avant de monter.
                    try? await Task.sleep(for: .milliseconds(250))
                }
                withAnimation(.smooth(duration: 0.9)) { shown = value }
            }
    }
}

#Preview("Clair") {
    @Previewable @State var cents = 4800.0
    VStack(spacing: 16) {
        AnimatedCounter(value: cents, format: .money)
            .priceStyle(.largeTitle.bold())
            .foregroundStyle(.economie)
        AnimatedCounter(value: 1.2, format: .decimal(unit: "t"))
            .priceStyle()
        AnimatedCounter(value: 41, format: .reduction(unit: "km"))
            .priceStyle()
        Button("Ajouter 5 $") { cents += 500 }
            .buttonStyle(.glass)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .grenierBackground()
}

#Preview("Sombre") {
    AnimatedCounter(value: 390_000, format: .money)
        .priceStyle()
        .foregroundStyle(.economie)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    AnimatedCounter(value: 0.62, format: .percent)
        .priceStyle()
        .padding()
        .grenierBackground()
        .dynamicTypeSize(.accessibility5)
}
