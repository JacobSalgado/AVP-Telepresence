//
//  ImmersiveView.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation

struct ImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(SessionManager.self) private var sessionManager

    // Puzzle data
    @StateObject private var puzzleViewModel = PuzzleViewModel()
    @State private var hasLoadedPuzzle = false

    @State private var puzzleAnchor = Entity()
    @State private var interaction = PuzzleInteractionState()

    var body: some View {
        RealityView { content, attachments in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)

                if let whiteboard = attachments.entity(for: "whiteboard") {
                    whiteboard.name = "whiteboard"
                    whiteboard.position = [0, 0.85, -0.5]
                    whiteboard.scale = .one * 1.2
                    whiteboard.transform.rotation = simd_quatf(angle: Float(3 * Double.pi / 2), axis: SIMD3<Float>(1, 0, 0))
                    content.add(whiteboard)
                }

                guard let skyBox = generateSkyBox() else { return }
                content.add(skyBox)
            }

            puzzleAnchor.position = [0, 1.0, -0.8] // adjust placement to taste
            content.add(puzzleAnchor)
        }
        update: { content, attachments in
            for piece in puzzleViewModel.pieces {
                // Only create an entity for this piece the FIRST time we see
                // it. If one already exists, skip straight to the next piece.
                guard interaction.pieceEntities[piece.id] == nil else { continue }
                let entity = makePieceEntity(for: piece)
                puzzleAnchor.addChild(entity)
                interaction.pieceEntities[piece.id] = entity
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
                              let piece = pieceForEntity(value.entity) {
                        let group = puzzleViewModel.piecesInGroup(of: piece)

                        if interaction.dragStartPositions[piece.id] == nil {
                            for member in group {
                                interaction.dragStartPositions[member.id] = member.currentPosition
                            }
                        }

                        let translation3D = value.convert(value.translation3D, from: .local, to: value.entity.parent!)

                        for member in group {
                            guard let start = interaction.dragStartPositions[member.id] else { continue }
                            let newPos = start + translation3D
                            member.currentPosition = newPos
                            interaction.pieceEntities[member.id]?.position = newPos
                        }
                    }
                }
                .onEnded { value in
                    guard value.entity.name.hasPrefix("piece_"),
                          let piece = pieceForEntity(value.entity) else {return}

                    let group = puzzleViewModel.piecesInGroup(of: piece)
                    for member in group { interaction.dragStartPositions[member.id] = nil }

                    puzzleViewModel.handleDragEnded(draggedPiece: piece)

                    for member in group {
                        interaction.pieceEntities[member.id]?.position = member.currentPosition
                        if member.isPlaced {
                            interaction.pieceEntities[member.id]?.components.remove(InputTargetComponent.self)
                        }
                    }
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
    // Returns a VideoMaterial - main way of getting video material for app once video is obtained
    func generateVideoMaterial() -> VideoMaterial? {
        // URL that points to the video file. guard statement
        // is used to locate the URL of the video file at the
        // app's main bundle
        guard let url = Bundle.main.url(forResource: "test3", withExtension: "mp4")
        else
        {
            print("Error loading video")
            return nil
        }

        // AVPlayer instance to control the playback of the
        // video.
        let avPlayer = AVPlayer(url: url)

        // Instantiate and configure video material
        let videoMaterial = VideoMaterial(avPlayer: avPlayer)

        // iniates playback of the video
        avPlayer.play()

        // returns the VideoMaterial object
        return videoMaterial
    }

    /* Temporary Image Function until 360 video of room is provided */
    func generateImageMaterial() -> UnlitMaterial? {
        guard let texture = try? TextureResource.load(
            named: "dam_road.jpg"
        ) else {
            print("Failed to load panorama")
            return nil
        }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))

        return material
    }

    /* Skybox creation */
    func generateSkyBox() -> Entity?
    {
        /*
         creates a spherical mesh for the skybox with a radius of 1000 units.
         Starts by generating a spherical mesh, mesh is designed with a radius of 1000 units,
         providing a wide and immersive backdrop for the scene
         */
        let skyBoxMesh = MeshResource.generateSphere(radius: 1000)

        /*
        make skybox dynamic, video material
         */
        /*guard let videoMaterial = generateVideoMaterial()
        else
        {
            return nil
        }*/
        guard let imageMaterial = generateImageMaterial()
        else { return nil }

        /*
        Entity is constructed by combining the previously generated spherical mesh and the video material
         */
        /*let skyBoxEntity = ModelEntity(mesh: skyBoxMesh, materials: [videoMaterial])*/
        let skyBoxEntity = ModelEntity(
            mesh: skyBoxMesh,
            materials: [imageMaterial]
        )

        // Get skybox to appear correctly in scene
        skyBoxEntity.scale *= .init(x: -1, y: 1, z: 1)

        return skyBoxEntity
    }

    private func makePieceEntity(for piece: PuzzlePiece) -> ModelEntity {
        print("Creating entity for piece \(piece.id)")
        let mesh = MeshResource.generatePlane(width: piece.pieceSize.x, height: piece.pieceSize.y)

        var material = UnlitMaterial()
        if let texture = try? TextureResource.load(named: piece.imageName) {
            material.color = .init(texture: .init(texture))
        }
        material.blending = .transparent(opacity: .init(scale: 1.0))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "piece_\(piece.id)"
        entity.position = piece.currentPosition
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func pieceForEntity(_ entity: Entity) -> PuzzlePiece? {
        guard entity.name.hasPrefix("piece_"),
              let idString = entity.name.split(separator: "_").last,
              let id = Int(idString) else { return nil }
        return puzzleViewModel.pieces.first { $0.id == id }
    }
}

final class PuzzleInteractionState {
    var pieceEntities: [Int: ModelEntity] = [:]
    var dragStartPositions: [Int: SIMD3<Float>] = [:]
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
        .environment(SessionManager())
}
