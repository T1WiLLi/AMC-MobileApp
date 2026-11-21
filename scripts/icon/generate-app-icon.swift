#!/usr/bin/env swift
// Génère l'icône d'app de Grenier (1024×1024, PNG) en trois variantes iOS 18+ :
// claire (AppIcon.png), sombre (AppIcon-Dark.png) et teintée (AppIcon-Tinted.png).
//
// Usage (depuis la racine du repo, macOS avec Xcode) :
//   swift scripts/icon/generate-app-icon.swift [dossier-de-sortie]
// Par défaut, écrit dans AMC-MobileApp/Assets.xcassets/AppIcon.appiconset/.
// Aucune dépendance externe : SwiftUI + ImageRenderer + ImageIO.

import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Variant { case light, dark, tinted }

struct IconView: View {
    let variant: Variant
    let size: CGFloat = 1024

    @ViewBuilder var background: some View {
        switch variant {
        case .light:
            // Dégradé Grenier chaud : plus lumineux en haut, plus profond en bas.
            ZStack {
                LinearGradient(colors: [Color(hex: 0xD2692B), Color(hex: 0xB4521A), Color(hex: 0x8E3D10)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xF4A061, opacity: 0.45), .clear],
                               center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: 560)
            }
        case .dark:
            ZStack {
                LinearGradient(colors: [Color(hex: 0x221B15), Color(hex: 0x14110E)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xF08A4B, opacity: 0.16), .clear],
                               center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 520)
            }
        case .tinted:
            Color.clear
        }
    }

    var basketStyle: AnyShapeStyle {
        switch variant {
        case .light:
            AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFFCF6), Color(hex: 0xF3E6D2)],
                                         startPoint: .top, endPoint: .bottom))
        case .dark:
            AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF6A06A), Color(hex: 0xE57A38)],
                                         startPoint: .top, endPoint: .bottom))
        case .tinted:
            AnyShapeStyle(LinearGradient(colors: [Color(white: 1), Color(white: 0.78)],
                                         startPoint: .top, endPoint: .bottom))
        }
    }

    var leafColor: Color {
        switch variant {
        case .light: Color(hex: 0x1F7A4A)
        case .dark: Color(hex: 0x4CC488)
        case .tinted: Color(white: 0.62)
        }
    }

    var shadowColor: Color {
        switch variant {
        case .light: Color(hex: 0x4A1E05, opacity: 0.35)
        case .dark: Color.black.opacity(0.5)
        case .tinted: Color.clear
        }
    }

    var body: some View {
        ZStack {
            background
            ZStack {
                // Feuille (Économie) qui dépasse du panier, derrière le rebord.
                Image(systemName: "leaf.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220)
                    .foregroundStyle(leafColor)
                    .rotationEffect(.degrees(50))
                    .offset(x: 30, y: -175)
                Image(systemName: "basket.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 600)
                    .foregroundStyle(basketStyle)
                    .shadow(color: shadowColor, radius: 28, x: 0, y: 22)
            }
            .offset(y: 50)
        }
        .frame(width: size, height: size)
    }
}

@MainActor
func render(_ variant: Variant, to url: URL) throws {
    let renderer = ImageRenderer(content: IconView(variant: variant))
    renderer.scale = 1
    renderer.isOpaque = variant != .tinted
    guard let cg = renderer.cgImage else { throw NSError(domain: "icon", code: 1) }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "icon", code: 2) }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 3) }
    print("écrit \(url.path) (\(cg.width)×\(cg.height))")
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                 ?? "AMC-MobileApp/Assets.xcassets/AppIcon.appiconset")
try MainActor.assumeIsolated {
    try render(.light, to: outDir.appendingPathComponent("AppIcon.png"))
    try render(.dark, to: outDir.appendingPathComponent("AppIcon-Dark.png"))
    try render(.tinted, to: outDir.appendingPathComponent("AppIcon-Tinted.png"))
}
