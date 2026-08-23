//
//  AppModel.swift
//  AVP Telepresence
//
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
