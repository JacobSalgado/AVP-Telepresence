//
//  ImmersiveView.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI
import RealityKit
import RealityKitContent
import Combine

struct ImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(SessionManager.self) private var sessionManager
    
    @State private var sceneModel = ImmersiveSceneModel()

    // Puzzle data
    @State private var puzzleViewModel = PuzzleViewModel()
    @State private var hasLoadedPuzzle = false

    
    

    // Throttle for how often we broadcast live drag positions. 15-20x/sec
    // is plenty smooth without flooding the messenger.
    private let dragBroadcastInterval: TimeInterval = 0.06

    // MARK: - Placement tuning
    // Sudoku/whiteboard: vertical, in front of the user, roughly eye level.
    private let whiteboardPosition: SIMD3<Float> = [0, 1.3, -1.2]
    
    var body: some View {
        RealityView { content, attachments in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)

                if let whiteboard = attachments.entity(for: "whiteboard") {
                    whiteboard.name = "whiteboard"
                    whiteboard.position = whiteboardPosition
                    whiteboard.scale = .one * 1.2
                    // Attachments already face forward (+Z normal) by default,
                    // which is exactly "vertical, facing the user" — no
                    // rotation needed. If the content appears mirrored or
                    // backwards, try a 180° rotation about Y instead:
                    // whiteboard.transform.rotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                    content.add(whiteboard)
                }
            }

            
            

            let referenceCard = sceneModel.makeReferenceCardEntity()
            content.add(referenceCard)

            
        }
        update: { content, attachments in
            for piece in puzzleViewModel.pieces {
                // Only create an entity for this piece the FIRST time we see
                // it. If one already exists, skip straight to the next piece.
                guard sceneModel.interaction.pieceEntities[piece.id] == nil else { continue }
                let entity = sceneModel.makePieceEntity(for: piece)
                // puzzleAnchor.addChild(entity)
                sceneModel.interaction.pieceEntities[piece.id] = entity
            }
        }
        attachments: {
            Attachment(id: "whiteboard") {
                WhiteboardView()
            }
        }
        .task {
            guard !hasLoadedPuzzle else { return }
            hasLoadedPuzzle = true
            puzzleViewModel.loadPuzzle()

            // Hand SessionManager a reference so it can push incoming
            // network updates straight into the model.
            sessionManager.puzzleViewModel = puzzleViewModel

            // Whenever a remote participant's drag updates our local model,
            // animate the affected entities smoothly rather than snapping.
            puzzleViewModel.remoteUpdates
                .sink { update in
                    for (id, position) in update.positions {
                        guard let entity = sceneModel.interaction.pieceEntities[id] else { continue }
                        var transform = entity.transform
                        transform.translation = position
                        entity.move(to: transform, relativeTo: entity.parent, duration: 0.08)

                        if let isPlaced = update.isPlaced {
                            // Drag ended (remotely) — restore full opacity
                            // and update grabbability to match placement.
                            sceneModel.setPieceOpacity(id: id, scale: 1.0)
                            if isPlaced {
                                entity.components.remove(InputTargetComponent.self)
                            } else if entity.components[InputTargetComponent.self] == nil {
                                entity.components.set(InputTargetComponent())
                            }
                        } else {
                            // isPlaced == nil means someone else is still
                            // actively dragging this piece right now — show
                            // it semi-transparent here too, mirroring what
                            // they see locally on their own drag.
                            sceneModel.setPieceOpacity(id: id, scale: 0.55)
                        }
                    }
                }
                .store(in: &sceneModel.interaction.cancellables)
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged{ value in
                    // move entities
                    if value.entity.name == "whiteboard" {
                        let newPosition = value.convert(value.gestureValue.location3D, from: .local, to: .scene)
                        value.entity.position = newPosition
                    } else if value.entity.name.hasPrefix("piece_"),
                              let piece = sceneModel.pieceForEntity(value.entity) {
                        let group = puzzleViewModel.piecesInGroup(of: piece)

                        if sceneModel.interaction.dragStartPositions[piece.id] == nil {
                            for member in group {
                                sceneModel.interaction.dragStartPositions[member.id] = member.currentPosition
                                // See through the piece(s) you're holding so
                                // you can judge alignment against whatever's
                                // underneath, instead of it just visually
                                // blocking the piece below.
                                sceneModel.setPieceOpacity(id: member.id, scale: 0.55)
                            }
                        }

                        let translation3D = value.convert(value.translation3D, from: .local, to: value.entity.parent!)

                        for member in group {
                            guard let start = sceneModel.interaction.dragStartPositions[member.id] else { continue }
                            let newPos = start + translation3D
                            member.currentPosition = newPos
                            sceneModel.interaction.pieceEntities[member.id]?.position = newPos
                        }

                        // Throttled broadcast so remote participants see this
                        // drag happening live, without flooding the messenger.
                        let now = Date()
                        if now.timeIntervalSince(sceneModel.interaction.lastDragBroadcast) >= dragBroadcastInterval {
                            sceneModel.interaction.lastDragBroadcast = now
                            sessionManager.sendPuzzleDragUpdate(pieces: group)
                        }
                    }
                }
                .onEnded { value in
                    guard value.entity.name.hasPrefix("piece_"),
                          let piece = sceneModel.pieceForEntity(value.entity) else {return}

                    let group = puzzleViewModel.piecesInGroup(of: piece)
                    for member in group {
                        sceneModel.interaction.dragStartPositions[member.id] = nil
                        sceneModel.setPieceOpacity(id: member.id, scale: 1.0)
                    }

                    puzzleViewModel.handleDragEnded(draggedPiece: piece)

                    for member in group {
                        sceneModel.interaction.pieceEntities[member.id]?.position = member.currentPosition
                        if member.isPlaced {
                            sceneModel.interaction.pieceEntities[member.id]?.components.remove(InputTargetComponent.self)
                        }
                    }

                    // Broadcast the final, settled state (position + placed)
                    // so remote clients land in exactly the same spot.
                    sessionManager.sendPuzzleDragEnded(pieces: group)
                }
        )
        .simultaneousGesture(
            RotateGesture3D()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == "whiteboard" else {return}
                    let entity = value.entity
                    entity.orientation = simd_quatf(value.rotation) * entity.orientation
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == "whiteboard" else {return}
                    let entity = value.entity
                    entity.scale = .one * Float(value.magnification)
                }
            )
    }
}

final class PuzzleInteractionState {
    var pieceEntities: [String: ModelEntity] = [:]
    var dragStartPositions: [String: SIMD3<Float>] = [:]
    var lastDragBroadcast: Date = .distantPast
    var cancellables = Set<AnyCancellable>()
    /// Tracks each piece's last-applied opacity scale so setPieceOpacity
    /// can skip redundant material reassignment when nothing's changing.
    var currentOpacity: [String: Float] = [:]
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
        .environment(SessionManager())
}
