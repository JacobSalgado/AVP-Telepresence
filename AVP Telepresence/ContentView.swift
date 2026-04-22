//
//  ContentView.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//
import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {

    @State private var showImmersiveSpace = false
    @State private var glowPulse = false
    @State private var orbitAngle: Double = 0

    @Environment(\.openWindow) var openWindow
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        ZStack {
            // Ambient background glow
            RadialGradient(
                colors: [
                    Color(red: 0.05, green: 0.35, blue: 0.55).opacity(0.4),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 300
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {

                // ── Hero orb ──────────────────────────────────────────────
                ZStack {
                    // Outer halo rings
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                Color.cyan.opacity(0.12 - Double(i) * 0.03),
                                lineWidth: 1
                            )
                            .frame(width: CGFloat(160 + i * 40),
                                   height: CGFloat(160 + i * 40))
                            .rotationEffect(.degrees(orbitAngle * Double(i + 1) * 0.4))
                    }

                    // Glow bloom
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.cyan.opacity(glowPulse ? 0.45 : 0.25),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 90
                            )
                        )
                        .frame(width: 160, height: 160)
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: glowPulse
                        )

                    // RealityKit sphere
                    RealityView { content in
                        var mat = PhysicallyBasedMaterial()
                        mat.baseColor = .init(tint: UIColor(
                            red: 0.55, green: 0.92, blue: 1.0, alpha: 1.0))
                        mat.roughness = .init(floatLiteral: 0.15)
                        mat.metallic  = .init(floatLiteral: 0.85)
                        let orb = ModelEntity(
                            mesh: .generateSphere(radius: 0.055),
                            materials: [mat])
                        content.add(orb)
                    }
                    .frame(width: 120, height: 120)
                }
                .frame(height: 200)
                .onAppear {
                    glowPulse = true
                    withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                        orbitAngle = 360
                    }
                }

                // ── Title block ───────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("AVP TELEPRESENCE")
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .tracking(8)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.cyan.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Collaborative Presence Study")
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.45))
                }

                // ── Divider ───────────────────────────────────────────────
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.cyan.opacity(0.4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .frame(maxWidth: 260)

                // ── Action buttons ────────────────────────────────────────
                VStack(spacing: 14) {
                    TelPresenceButton(
                        label: "View Instructions",
                        icon: "doc.text",
                        style: .secondary
                    ) {
                        openWindow(id: "Instructions")
                    }

                    TelPresenceButton(
                        label: showImmersiveSpace ? "Exit Immersive Space" : "Enter Immersive Space",
                        icon: showImmersiveSpace ? "xmark.circle" : "globe",
                        style: .primary
                    ) {
                        Task {
                            if showImmersiveSpace {
                                await dismissImmersiveSpace()
                                showImmersiveSpace = false
                            } else {
                                await openImmersiveSpace(id: "VideoImmersiveView")
                                showImmersiveSpace = true
                            }
                        }
                    }
                }

                // ── Status badge ──────────────────────────────────────────
                HStack(spacing: 6) {
                    Circle()
                        .fill(showImmersiveSpace ? Color.green : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .shadow(color: showImmersiveSpace ? .green : .clear, radius: 4)
                    Text(showImmersiveSpace ? "Space Active" : "Space Inactive")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 4)
            }
            .padding(40)
        }
        .frame(width: 440, height: 580)
    }
}

// ── Reusable button component ─────────────────────────────────────────────────

enum TelPresenceButtonStyle { case primary, secondary }

struct TelPresenceButton: View {
    let label: String
    let icon: String
    let style: TelPresenceButtonStyle
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                Text(label)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .tracking(0.5)
            }
            .foregroundStyle(style == .primary ? .black : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                if style == .primary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.9), Color(red: 0.1, green: 0.6, blue: 0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .frame(width: 280)
        .onHover { isHovered = $0 }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
