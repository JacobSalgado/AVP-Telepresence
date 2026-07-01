//
//  InstructionsView.swift
//  AVP Telepresence
//
//  Created by Research on 1/31/26.
//

import SwiftUI
import RealityKit
import RealityKitContent

let instructionsText = "How to use AVP Telepresence:\n\n1. Launch the app on your iOS device.\n2. Tap the 'Join' button to connect to the host.\n3. Use your device's camera to track the host's avatar.\n4. Move your avatar around the virtual environment to interact with the host.\n\nHave fun!";

struct InstructionsView: View {

    var body: some View {

            Text(instructionsText)
                //.background(.red)
                .font(.title)
                //.foregroundColor(.green)
    }
}
#Preview {
    InstructionsView()
}
