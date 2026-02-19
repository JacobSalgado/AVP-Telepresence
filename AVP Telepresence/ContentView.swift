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
    // variable to control the visibility of the imm space
    @State var showImmersiveSpace = false
    
    @Environment(\.openWindow) var openWindow // Allows you to open up a new window screen
    
    // Open the space
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    
    // Dismiss the space window
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace // close immersive space

    var body: some View {
        
        // Switch the visibility of the immersive space
        Toggle(showImmersiveSpace ? "Back to Reality" : "Show Immersive space", isOn: $showImmersiveSpace)
            .toggleStyle(.button)
            
            // Trigger action when the value of showImmersiveSpace changes
            .onChange(of: showImmersiveSpace) { _, newValue in
                // asynchronous task for handling opening or dismissing the immersive space
                Task
                {
                    if newValue
                    {
                        await openImmersiveSpace(id: "VideoImmersiveView")
                    }
                    else
                    {
                        await dismissImmersiveSpace()
                    }
                }
            }
            // adjust control size of the toggle
            .controlSize(.extraLarge)
        
        VStack {
            /*Model3D(named: "Scene", bundle: realityKitContentBundle)
                .padding(.bottom, 50)*/

            Text("Welcome to AVP Telepresence!")
                //.background(.red)
                .font(.title)
                .foregroundColor(.green)
            
            Button {
                openWindow(id: "Instructions");
            } label: {
                Text("Open Instructions")
            }
            Button {
                openWindow(id: "VideoPlayer");
            } label: {
                Text("Open 360 Video")
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
