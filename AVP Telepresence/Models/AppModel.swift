//
//  AppModel.swift
//  AVP Telepresence
//
//

import SwiftUI
import RealityKit
import Foundation

/// TODO: Store all entities in array here rather than having it in the immersive view
/// TODO: Generate the entities and CLEAR the entities

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    static let immersiveSpaceID = "VideoImmersiveView"
    enum ImmersiveSpaceState { case closed, inTransition, open }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    var whiteboardStrokes: [WhiteboardStroke] = []
    
    private var puzzlePieces: [PuzzlePiece] = []
    
    /*func spawnPuzzlePiece() -> PuzzlePiece {
        return PuzzlePiece()
    }*/
    
    /*func spawnSudokuBoard() -> TileSudokuModel {
        return SudokuBoard()
    }*/
    
    func clearAllEntities() {
        
    }
}
