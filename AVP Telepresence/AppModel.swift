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
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    // card states which can be accessible by both the ImmmersiveView and SessionManager
    var cards: [UUID: CardModel] = [:]
    var cardGroups: [UUID: Set<UUID>] = [:]
    var groupLabels: [UUID: String] = [:]
    
    var cardEntities: [UUID: ModelEntity] = [:]
    
    var categoryZones: [String: Entity] = [:]
    var highlightedZone: String? = nil
    
    var reactionAnchor: Entity? = nil
    
    var pendingReaction: (gesture: ReactionGesture, position: SIMD3<Float>)? = nil
}

// struct of each card
struct CardModel: Codable, Identifiable {
    let id: UUID
    let label: String
    var transform: CodableTransform
    var groupID: UUID?
}
