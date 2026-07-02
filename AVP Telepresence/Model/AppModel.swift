//
//  AppModel.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI
import RealityKit
import Foundation

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "VideoImmersiveView"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    var whiteboardStrokes: [WhiteboardStroke] = []
}
