//
//  ContentView.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//
import SwiftUI
import RealityKit
import RealityKitContent
import GroupActivities

struct ContentView: View {
    @State private var showImmersiveSpace = false
    @State private var glowPulse = false
    @State private var orbitAngle: Double = 0
    
    @State private var groupStateObserver = GroupStateObserver()

    @Environment(\.openWindow) var openWindow
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(AppModel.self) private var appModel
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        ZStack {
            backgroundGlow
            mainContent
        }
        .frame(width: 440, height: 580)
        .onChange(of: sessionManager.shouldBeImmersed) { _, shouldBeImmersed in
            guard shouldBeImmersed, !showImmersiveSpace else { return }
            Task {
                await openImmersiveSpace(id: appModel.immersiveSpaceID)
                showImmersiveSpace = true
            }
        }
    }
    
    // ── Extracted background ────────────────────────────────────────
    private var backgroundGlow: some View {
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
    }
    
    // ── Extracted main vertical stack ───────────────────────────────
    private var mainContent: some View {
        VStack(spacing: 32) {
            heroOrb
            titleBlock
            divider
            actionButtons
            statusBadge
        }
        .padding(40)
    }
    
    // ── Hero orb ─────────────────────────────────────────────────────
    private var heroOrb: some View {
        ZStack {
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
            Text(sessionManager.session != nil ? "In session!!!" : "Not in session")
            .frame(width: 120, height: 120)
            Text(sessionManager.activationState)
                .frame(width: 120, height: 120)
                .font(.caption)
                .foregroundStyle(.orange)
                .offset(y: 20)
            Text(groupStateObserver.isEligibleForGroupSession ? "Eligible" : "Not Eligible")
                .font(.caption)
                .foregroundStyle(.yellow)
                .offset(y:40)
        }
        .frame(height: 200)
        .onAppear {
            glowPulse = true
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                orbitAngle = 360
            }
        }
    }
    
    // ── Title block ──────────────────────────────────────────────────
    private var titleBlock: some View {
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
    }
    
    // ── Divider ───────────────────────────────────────────────────────
    private var divider: some View {
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
    }
    
    // ── Action buttons ─────────────────────────────────────────────────
    private var actionButtons: some View {
        VStack(spacing: 14) {
            TelPresenceButton(
                label: "Start SharePlay",
                icon: "shareplay",
                style: .secondary
            ){
                sessionManager.startSharePlay()
            }
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
                if showImmersiveSpace {
                    Task {
                        await dismissImmersiveSpace()
                        showImmersiveSpace = false
                        sessionManager.requestExitImmersion()
                    }
                } else {
                    sessionManager.requestImmersion()
                }
            }
        }
    }
    
    // ── Status badge ────────────────────────────────────────────────────
    private var statusBadge: some View {
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
        .environment(SessionManager())
}
