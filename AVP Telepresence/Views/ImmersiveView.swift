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
import Combine

struct ImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(SessionManager.self) private var sessionManager

    // Puzzle data
    @StateObject private var puzzleViewModel = PuzzleViewModel()
    @State private var hasLoadedPuzzle = false

    @State private var puzzleAnchor = Entity()
    // Shared across all pieces so their relative transparency draw order is
    // explicit and stable, instead of RealityKit's default per-entity
    // center-distance heuristic (which flickers when pieces' meshes overlap
    // heavily — see makePieceEntity).
    @State private var puzzleSortGroup = ModelSortGroup()
    @State private var interaction = PuzzleInteractionState()

    // Throttle for how often we broadcast live drag positions. 15-20x/sec
    // is plenty smooth without flooding the messenger.
    private let dragBroadcastInterval: TimeInterval = 0.06

    // MARK: - Placement tuning
    // Sudoku/whiteboard: vertical, in front of the user, roughly eye level.
    private let whiteboardPosition: SIMD3<Float> = [0, 1.3, -1.2]

    // Jigsaw table: positioned off to the side so it doesn't overlap the
    // whiteboard, at typical table height.
    private let tableHeight: Float = 0.75
    private let tablePosition: SIMD3<Float> = [0, 0, 0] // XZ placement; Y is the floor, table sits on top
    private let tableTopSize: SIMD2<Float> = [0.75, 0.65]     // width, depth — sized around the ~0.28m puzzle board
    private let tableThickness: Float = 0.04

    // Reference card: stands upright beside the table (not on top of it,
    // so it doesn't compete with tabletop space where pieces scatter).
    private let referenceCardWidth: Float = 0.22
    private let referenceCardSideMargin: Float = 0.06 // gap from the table's edge
    private let referenceCardTiltDegrees: Float = 12   // slight backward lean for readability

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

                guard let skyBox = generateSkyBox() else { return }
                content.add(skyBox)
            }

            // Table model, so the puzzle reads as "resting on a table"
            // rather than floating in space.
            let table = makeTableEntity()
            content.add(table)

            let referenceCard = makeReferenceCardEntity()
            content.add(referenceCard)

            // Puzzle pieces sit just above the tabletop surface.
            puzzleAnchor.position = [tablePosition.x,
                                      tableHeight + 0.002,
                                      tablePosition.z]
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

            // Hand SessionManager a reference so it can push incoming
            // network updates straight into the model.
            sessionManager.puzzleViewModel = puzzleViewModel

            // Whenever a remote participant's drag updates our local model,
            // animate the affected entities smoothly rather than snapping.
            puzzleViewModel.remoteUpdates
                .sink { update in
                    for (id, position) in update.positions {
                        guard let entity = interaction.pieceEntities[id] else { continue }
                        var transform = entity.transform
                        transform.translation = position
                        entity.move(to: transform, relativeTo: entity.parent, duration: 0.08)

                        if let isPlaced = update.isPlaced {
                            // Drag ended (remotely) — restore full opacity
                            // and update grabbability to match placement.
                            setPieceOpacity(id: id, scale: 1.0)
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
                            setPieceOpacity(id: id, scale: 0.55)
                        }
                    }
                }
                .store(in: &interaction.cancellables)
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
                                // See through the piece(s) you're holding so
                                // you can judge alignment against whatever's
                                // underneath, instead of it just visually
                                // blocking the piece below.
                                setPieceOpacity(id: member.id, scale: 0.55)
                            }
                        }

                        let translation3D = value.convert(value.translation3D, from: .local, to: value.entity.parent!)

                        for member in group {
                            guard let start = interaction.dragStartPositions[member.id] else { continue }
                            let newPos = start + translation3D
                            member.currentPosition = newPos
                            interaction.pieceEntities[member.id]?.position = newPos
                        }

                        // Throttled broadcast so remote participants see this
                        // drag happening live, without flooding the messenger.
                        let now = Date()
                        if now.timeIntervalSince(interaction.lastDragBroadcast) >= dragBroadcastInterval {
                            interaction.lastDragBroadcast = now
                            sessionManager.sendPuzzleDragUpdate(pieces: group)
                        }
                    }
                }
                .onEnded { value in
                    guard value.entity.name.hasPrefix("piece_"),
                          let piece = pieceForEntity(value.entity) else {return}

                    let group = puzzleViewModel.piecesInGroup(of: piece)
                    for member in group {
                        interaction.dragStartPositions[member.id] = nil
                        setPieceOpacity(id: member.id, scale: 1.0)
                    }

                    puzzleViewModel.handleDragEnded(draggedPiece: piece)

                    for member in group {
                        interaction.pieceEntities[member.id]?.position = member.currentPosition
                        if member.isPlaced {
                            interaction.pieceEntities[member.id]?.components.remove(InputTargetComponent.self)
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

    /// A simple placeholder table: a flat tabletop slab plus four legs,
    /// positioned at `tablePosition` (XZ) with its top surface at
    /// `tableHeight`. Swap the materials for something nicer once you have
    /// real art, or replace this whole function with a loaded USDZ model.
    private func makeTableEntity() -> Entity {
        let table = Entity()
        table.name = "puzzleTable"

        let woodMaterial = SimpleMaterial(color: .init(red: 0.45, green: 0.30, blue: 0.18, alpha: 1.0),
                                           roughness: 0.6, isMetallic: false)

        // Tabletop slab, centered so its TOP face sits at tableHeight.
        let topMesh = MeshResource.generateBox(width: tableTopSize.x,
                                                height: tableThickness,
                                                depth: tableTopSize.y)
        let top = ModelEntity(mesh: topMesh, materials: [woodMaterial])
        top.position = [tablePosition.x,
                         tableHeight - tableThickness / 2,
                         tablePosition.z]
        table.addChild(top)

        // Four legs running from the underside of the tabletop down to the floor.
        let legThickness: Float = 0.05
        let legHeight = tableHeight - tableThickness
        let legMesh = MeshResource.generateBox(width: legThickness, height: legHeight, depth: legThickness)

        let insetX = tableTopSize.x / 2 - legThickness
        let insetZ = tableTopSize.y / 2 - legThickness
        let legOffsets: [SIMD2<Float>] = [
            [ insetX,  insetZ], [ insetX, -insetZ],
            [-insetX,  insetZ], [-insetX, -insetZ]
        ]

        for offset in legOffsets {
            let leg = ModelEntity(mesh: legMesh, materials: [woodMaterial])
            leg.position = [tablePosition.x + offset.x,
                             legHeight / 2,
                             tablePosition.z + offset.y]
            table.addChild(leg)
        }

        return table
    }

    /// Adjusts how see-through a piece is at runtime. Used to make the
    /// piece(s) currently being dragged (locally or by a remote
    /// participant) partially transparent, so alignment against whatever's
    /// underneath is visible, then restored to full opacity on release.
    /// scale: 1.0 = fully opaque (normal), lower = more see-through.
    ///
    /// Skips the material reassignment entirely if this piece is already
    /// at the requested opacity — during a drag this gets called on every
    /// throttled update (~16x/sec), so without this check we'd be
    /// rebuilding and reassigning an identical material dozens of times
    /// for no visual change.
    private func setPieceOpacity(id: String, scale: Float) {
        guard interaction.currentOpacity[id] != scale else { return }
        guard let entity = interaction.pieceEntities[id],
              var material = entity.model?.materials.first as? UnlitMaterial else { return }
        material.blending = .transparent(opacity: .init(scale: scale))
        entity.model?.materials = [material]
        interaction.currentOpacity[id] = scale
    }

    /// A standing reference card showing the assembled puzzle image, placed
    /// just beside the table (not on its surface) so it doesn't compete
    /// with the tabletop space pieces scatter across. Add the preview
    /// image to your Asset Catalog as an image set named "puzzlePreview".
    private func makeReferenceCardEntity() -> Entity {
        let card = Entity()
        card.name = "referenceCard"

        // Match the card's aspect ratio to the preview image itself so it
        // doesn't look stretched. Falls back to the puzzle board's own
        // aspect if the texture can't be loaded for some reason.
        var aspect: Float = 1.62
        if let texture = try? TextureResource.load(named: "puzzlePreview") {
            aspect = Float(texture.width) / Float(texture.height)
        }
        let cardHeight = referenceCardWidth / aspect

        var material = UnlitMaterial()
        if let texture = try? TextureResource.load(named: "puzzlePreview") {
            material.color = .init(texture: .init(texture))
        }
        material.blending = .opaque // reference image has no transparency to worry about

        // generatePlane(width:height:) is the UPRIGHT overload (XY-plane,
        // facing +Z) — this is the one case where we actually want that,
        // unlike the flat-on-the-table piece meshes.
        let mesh = MeshResource.generatePlane(width: referenceCardWidth, height: cardHeight)
        let imageEntity = ModelEntity(mesh: mesh, materials: [material])
        card.addChild(imageEntity)

        // Position: just past the table's right-hand edge (+X), bottom
        // edge resting at table height, centered on the table's depth.
        // NOTE: "right-hand edge" assumes the user approaches the table
        // from roughly the -Z direction, matching how tablePosition/
        // whiteboardPosition are set up elsewhere in this file — adjust
        // the X sign or swap to -Z placement if that doesn't match your
        // actual room layout once you see it in headset.
        let cardX = tablePosition.x + tableTopSize.x / 2 + referenceCardSideMargin + referenceCardWidth / 2
        let cardY = tableHeight + cardHeight / 2
        let cardZ = tablePosition.z
        card.position = [cardX, cardY, cardZ]

        // Face back toward the table/user, with a slight backward tilt so
        // it reads comfortably from a standing height looking down/across
        // rather than dead-on. Adjust referenceCardTiltDegrees to taste.
        let faceTowardTable = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        let tiltBack = simd_quatf(angle: referenceCardTiltDegrees * .pi / 180, axis: [1, 0, 0])
        card.transform.rotation = faceTowardTable * tiltBack

        return card
    }

    private func makePieceEntity(for piece: PuzzlePiece) -> ModelEntity {
        print("Creating entity for piece \(piece.id)")
        // generatePlane(width:depth:) lies FLAT in the XZ-plane (normal +Y) —
        // this is the correct overload for "resting on a table." The other
        // overload, generatePlane(width:height:), stands upright instead.
        let mesh = MeshResource.generatePlane(width: piece.pieceSize.x, depth: piece.pieceSize.y)

        var material = UnlitMaterial()
        if let texture = try? TextureResource.load(named: piece.imageName) {
            material.color = .init(texture: .init(texture))
        }
        material.blending = .transparent(opacity: .init(scale: 1.0))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "piece_\(piece.id)"
        entity.position = piece.currentPosition
        // Explicit, stable transparency draw order — same relative
        // ordering as the yBias in PuzzlePiece. This is what actually
        // fixes the angle-dependent flicker: RealityKit's default sort is
        // per-entity center-distance, which is unreliable when pieces'
        // (mostly-transparent) meshes overlap as heavily as these do.
        entity.components.set(ModelSortGroupComponent(group: puzzleSortGroup, order: piece.sortOrder))
        // generatePlane already lies flat (XZ-plane, normal +Y) — that's
        // exactly "resting on a table," so no rotation is applied here.
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func pieceForEntity(_ entity: Entity) -> PuzzlePiece? {
        guard entity.name.hasPrefix("piece_") else { return nil }
        let id = String(entity.name.dropFirst("piece_".count))
        return puzzleViewModel.pieces.first { $0.id == id }
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
