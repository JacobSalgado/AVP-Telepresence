//
//  ImmersiveSceneModel.swift
//  AVP Telepresence
//
//  Created by Research on 8/25/26.
//

import SwiftUI
import RealityKit
import Observation
import Combine
import AVFoundation

@Observable
final class ImmersiveSceneModel: ObservableObject {
    
    @State private var puzzleAnchor = Entity()
    @State public var interaction = PuzzleInteractionState() // public to give it to the ImmersiveView
    
    // Shared across all pieces so their relative transparency draw order is
    // explicit and stable, instead of RealityKit's default per-entity
    // center-distance heuristic (which flickers when pieces' meshes overlap
    // heavily — see makePieceEntity).
    @State private var puzzleSortGroup = ModelSortGroup()
    
    // Puzzle data
    @StateObject private var puzzleViewModel = PuzzleViewModel()
    
    let rootEntity = Entity()
    
    var tableEntity: ModelEntity?
    var puzzleEntity: Entity?
    var environmentEntity: Entity?
    
    // Jigsaw table: positioned off to the side so it doesn't overlap the
    // whiteboard, at typical table height.
    private let tableHeight: Float = 0.75
    private let tablePosition: SIMD3<Float> = [0, 0, 0] // XZ placement; Y is the floor, table sits on top
    private let tableRadius: Float = 0.35     // width, depth — sized around the ~0.28m puzzle board
    private let tableThickness: Float = 0.04
    
    // Reference card: stands upright beside the table (not on top of it,
    // so it doesn't compete with tabletop space where pieces scatter).
    private let referenceCardWidth: Float = 0.22
    private let referenceCardSideMargin: Float = 0.06 // gap from the table's edge
    private let referenceCardTiltDegrees: Float = 12   // slight backward lean for readability

    
    func createScene() async -> Entity {
        await loadEnvironment()
        
        return rootEntity
    }
    
    private func loadTable() {
        // Table model, so the puzzle reads as "resting on a table"
        // rather than floating in space.
        let _table = makeTableEntity()
        // content.add(table)
        
        
    }
    
    private func loadPuzzle() {
        // Puzzle pieces sit just above the tabletop surface.
        puzzleAnchor.position = [tablePosition.x,
                                  tableHeight + 0.002,
                                  tablePosition.z]
    }
    
    private func loadEnvironment() async {
        
        
        guard let _skyBox = generateSkyBox() else { return }
        // content.add(skyBox)
    }
    
    /**
     Everything below is related to creating the skybox and gathering the information to create the background environment. Set up for both image and video.
     Must be at least 4K video quality to look "realistic", otherwise you'll be able to to tell that it is blurry
     */
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
    private func generateImageMaterial() -> UnlitMaterial? {
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
    private func generateSkyBox() -> Entity?
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
    
    // ------------------------------------------------------------------------
    
    /// A simple placeholder table: a flat tabletop slab plus four legs,
    /// positioned at `tablePosition` (XZ) with its top surface at
    /// `tableHeight`. Swap the materials for something nicer once you have
    /// real art, or replace this whole function with a loaded USDZ model.
    private func makeTableEntity() -> Entity {
        let table = Entity()
        table.name = "puzzleTable"

        let woodMaterial = UnlitMaterial(color: .init(red: 0.9646, green: 0.8353, blue: 0.5843, alpha: 1.0))

        // Tabletop slab, centered so its TOP face sits at tableHeight.
        let topMesh = MeshResource.generateCylinder(height: tableThickness, radius: tableRadius)
        let top = ModelEntity(mesh: topMesh, materials: [woodMaterial])
        top.position = [tablePosition.x,
                         tableHeight - tableThickness / 2,
                         tablePosition.z]
        table.addChild(top)

        // Four legs running from the underside of the tabletop down to the floor.
        let legThickness: Float = 0.05
        let legHeight = tableHeight - tableThickness
        let legMesh = MeshResource.generateBox(width: legThickness, height: legHeight, depth: legThickness)

        let insetX = (tableRadius / 2) - legThickness
        let insetZ = (tableRadius / 2) - legThickness
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
    /// Public to provide access to ImmersiveView
    public func setPieceOpacity(id: String, scale: Float) {
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
    /// Puublic for ImmersiveView access
    public func makeReferenceCardEntity() -> Entity {
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
        let cardX = tablePosition.x + tableRadius / 2 + referenceCardSideMargin + referenceCardWidth / 2
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
    
    // Public for ImmersiveView
    public func makePieceEntity(for piece: PuzzlePiece) -> ModelEntity {
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

    // pub for immersiveview
    public func pieceForEntity(_ entity: Entity) -> PuzzlePiece? {
        guard entity.name.hasPrefix("piece_") else { return nil }
        let id = String(entity.name.dropFirst("piece_".count))
        return puzzleViewModel.pieces.first { $0.id == id }
    }
    
}

