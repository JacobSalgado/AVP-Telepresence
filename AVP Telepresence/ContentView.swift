//
//  ContentView.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI
import RealityKit
import RealityKitContent

let title = "Welcome to Telepresence";

struct ContentView: View {
    
    @State private var transform: AffineTransform3D = .identity
    @State private var opacity: CGFloat = 1
    
    // variable to control the visibility of the imm space
    @State var showImmersiveSpace = false
    
    @Environment(\.openWindow) var openWindow // Allows you to open up a new window screen
    
    // Open the space
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    
    // Dismiss the space window
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace // close immersive space
    
    @Environment(SessionManager.self) private var sessionManager
    
    var body: some View {
        VStack {
            RealityView { content in
                let model = ModelEntity(
                    mesh: .generateSphere(radius: 0.1),
                    materials: [SimpleMaterial(color: .white, isMetallic: true)])
                content.add(model)
            }
            .frame(height: 200)
            
            Text("Welcome to AVP Telepresence!")
                .font(.largeTitle)
                .foregroundColor(.green)
            
            Button{
                openWindow(id: "Instructions")
            } label: {
                Text("Open Instructions")
            }
            
            Button {
                Task {
                    if showImmersiveSpace{
                        await dismissImmersiveSpace()
                        showImmersiveSpace = false
                    } else {
                        await openImmersiveSpace(id: "VideoImmersiveView")
                        showImmersiveSpace = true
                    }
                }
            } label: {
                Text(showImmersiveSpace ? "Close 360 Video" : "Open 360 Video")
            }
            Toggle(showImmersiveSpace ? "Back to Reality" : "Show Immersive Space",
                   isOn: $showImmersiveSpace)
            .toggleStyle(.button)
            .controlSize(.extraLarge)
            .onChange(of: showImmersiveSpace) {_, newValue in
                Task {
                    if newValue {
                        await openImmersiveSpace(id: "VideoImmersiveView")
                    } else {
                        await dismissImmersiveSpace()
                    }
                }
            }
            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}
    #Preview(windowStyle: .automatic) {
        ContentView()
            .environment(AppModel())
    }
