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
    
    @Environment(\.openWindow) var openWindow // Allows you to open up a new window screen

    var body: some View {
        
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

            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}


#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
