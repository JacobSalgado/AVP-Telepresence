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
            titleBlock
            divider
            actionButtons
            statusBadge
        }
        .padding(40)
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
