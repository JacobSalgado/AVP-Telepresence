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
    
    @State private var handTracker = HandTrackingManager()
    
    //@State private var cardEntity: ModelEntity? = nil

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)

                // Skybox Implementation
                guard let skyBox = generateSkyBox() else { return }
                content.add(skyBox)
                
                let anchor = Entity()
                content.add(anchor)
                await MainActor.run {
                    appModel.reactionAnchor = anchor
                }
                
                // Spawn category zones
                let categoryNames = ["Category 1", "Category 2", "Category 3", "Unsorted"]
                for (index, name) in categoryNames.enumerated() {
                    let zone = makeCategoryZone(label: name, index: index)
                    content.add(zone)
                    await MainActor.run {
                        appModel.categoryZones[name] = zone
                    }
                }
                
                // cards from AppModel data
                let cardLabels = ["Navigation", "Search", "Profile", "Settings", "Help"]
                for (index, label) in cardLabels.enumerated() {
                    let id = UUID()
                    let card = makeCard(
                        width: 0.1,
                        height: 0.15,
                        depth: 0.002,
                        label: label,
                        color: .white
                    )
                    // spreads cards in a row
                    card.position = SIMD3(
                        x: Float(index) * 0.15 - 0.3,
                        y: 1.5,
                        z: -0.6)
                    content.add(card)
                    
                    // stores the card entity and metadata together
                    let model = CardModel(
                        id: id,
                        label: label,
                        transform: CodableTransform(card.transform.matrix)
                    )
                    
                    await MainActor.run {
                        appModel.cards[id] = model
                        appModel.cardEntities[id] = card
                    }
                }
            }
        } update: { content in
            // fill code here for Swiftui changes
            // called whenever AppModel Changes
            // Applies any incoming remote updates to local entities
            for (id, cardModel) in appModel.cards {
                appModel.cardEntities[id]?.transform.matrix = cardModel.transform.matrix
            }
            
            // spawn remote reaction if one arrived
            if let reaction = appModel.pendingReaction {
                spawnReaction(gesture: reaction.gesture, at: reaction.position)
                appModel.pendingReaction = nil // clear after consuming
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged{ value in
                    // move card
                    guard let entity = value.entity as? ModelEntity,
                          let cardID = appModel.cardEntities.first(where: {$0.value == entity})?.key
                    else {return}
                    
                    let newPosition = value.convert(
                        value.gestureValue.location3D,
                        from: .local,
                        to: .scene
                    )
                    entity.position = newPosition
                    
                    // this updates AppModel and broadcast in one step
                    appModel.cards[cardID]?.transform = CodableTransform(entity.transform.matrix)
                    
                    // highlight which zone the card is hovering over
                    appModel.highlightedZone = nearestZone(to: newPosition)
                    
                    sessionManager.send(.objectMoved(
                        id: cardID,
                        transform: CodableTransform(entity.transform.matrix)
                    ))
                }
                .onEnded { value in
                    guard let entity = value.entity as? ModelEntity,
                          let cardID = appModel.cardEntities.first(where: { $0.value == entity })?.key
                    else {return}
                    
                    let position = value.convert(
                        value.gestureValue.location3D,
                        from: .local,
                        to: .scene
                    )
                    
                    // check if dropped into the zone
                    if let zoneName = nearestZone(to: position) {
                        snapCard(entity: entity, cardID: cardID, toZone: zoneName)
                    }
                    appModel.highlightedZone = nil
                }
        )
        .task {
            handTracker.onGestureDetected = { gesture, position in
                spawnReaction(gesture: gesture, at: position)
                // broadcast so the other headset sees it too
                sessionManager.send(.reactionFired(
                    gesture: gesture,
                    position: CodableTransform(
                        Transform(translation: position).matrix
                    )
                ))
            }
            await handTracker.start()
        }
    }
    // Returns a VideoMaterial
    func generateVideoMaterial() -> VideoMaterial? {
        // URL that points to the video file. guard statement
        // is used to locate the URL of the video file at the
        // app's main bundle
        guard let url = Bundle.main.url(forResource: "createwithswift.com-tutorial-create-an-immersive-experience-with-a-360-degree-video-in-visionos-video-asset", withExtension: "mp4")
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
        guard let videoMaterial = generateVideoMaterial()
        else
        {
            return nil
        }
        
        /*
        Entity is constructed by combining the previously generated spherical mesh and the video material
         */
        let skyBoxEntity = ModelEntity(mesh: skyBoxMesh, materials: [videoMaterial])
        
        // Get skybox to appear correctly in scene
        skyBoxEntity.scale *= .init(x: -1, y: 1, z: 1)
        
        return skyBoxEntity
    }
    
    /* Function for creating a brand new card */
    func makeCard(width: Float, height: Float, depth: Float, label: String, color: UIColor) -> ModelEntity {
        
        let bodyMesh = MeshResource.generateBox(
            width: width,
            height: height,
            depth: depth,
            cornerRadius: 0.005
        )
        
        let cardFace = CardFaceView(label: label, color: color)
        
        // render text at resoultion matching card proportions
        let renderer = ImageRenderer(content: cardFace)
        renderer.scale = 3.0
        renderer.proposedSize = .init(width:200, height:300)
        
        // convert to texture
        if let uiImage = renderer.uiImage,
           let cgImage = uiImage.cgImage,
           let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)){
            
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            
            // collision and inputs
            let cardBody = ModelEntity(mesh: bodyMesh, materials: [material])
            cardBody.generateCollisionShapes(recursive: false)
            cardBody.components.set(InputTargetComponent())
            return cardBody
        }
        
        // standard color card if texture fails
        var fallbackMaterial = PhysicallyBasedMaterial()
        fallbackMaterial.baseColor = .init(tint: color)
        fallbackMaterial.roughness = .init(floatLiteral: 0.8) // matte
        fallbackMaterial.metallic = .init(floatLiteral: 0.0)
        
        let cardBody  = ModelEntity(mesh: bodyMesh, materials: [fallbackMaterial])
        
        // for gesture handling
        cardBody.generateCollisionShapes(recursive: false)
        
        // enable input (pinch gestures, etc.)
        cardBody.components.set(InputTargetComponent())
        
        return cardBody
    }
    
    /**
     *  @brief positions cards within the category
     */
    func makeCategoryZone(label: String, index: Int) -> Entity {
        let zoneRoot = Entity()

        // Position zones in a row on a virtual table surface
        zoneRoot.position = SIMD3(
            x: Float(index) * 0.38 - 0.57,
            y: 1.2,
            z: -0.7
        )

        // ── Distinct color per zone ──────────────────────────────────────
        let zoneColors: [UIColor] = [
            UIColor(red: 0.35, green: 0.60, blue: 0.95, alpha: 0.6),  // blue
            UIColor(red: 0.35, green: 0.80, blue: 0.55, alpha: 0.6),  // green
            UIColor(red: 0.95, green: 0.65, blue: 0.25, alpha: 0.6),  // amber
            UIColor(red: 0.75, green: 0.40, blue: 0.90, alpha: 0.6),  // purple
        ]
        let color = zoneColors[index % zoneColors.count]

        // ── Box walls ────────────────────────────────────────────────────
        // Box is 28cm wide, 8cm tall, 22cm deep
        // Built from 5 thin panels: bottom, front, back, left, right (open top)
        let boxWidth:  Float = 0.28
        let boxHeight: Float = 0.08
        let boxDepth:  Float = 0.22
        let thickness: Float = 0.004

        let panels: [(width: Float, height: Float, depth: Float, x: Float, y: Float, z: Float)] = [
            // Bottom
            (boxWidth, thickness, boxDepth, 0, 0, 0),
            // Front wall
            (boxWidth, boxHeight, thickness, 0, boxHeight / 2, boxDepth / 2),
            // Back wall
            (boxWidth, boxHeight, thickness, 0, boxHeight / 2, -boxDepth / 2),
            // Left wall
            (thickness, boxHeight, boxDepth, -boxWidth / 2, boxHeight / 2, 0),
            // Right wall
            (thickness, boxHeight, boxDepth, boxWidth / 2, boxHeight / 2, 0),
        ]

        for panel in panels {
            let mesh = MeshResource.generateBox(
                width: panel.width,
                height: panel.height,
                depth: panel.depth,
                cornerRadius: 0.002
            )
            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: color)
            mat.roughness = .init(floatLiteral: 0.8)
            mat.metallic  = .init(floatLiteral: 0.0)

            let panelEntity = ModelEntity(mesh: mesh, materials: [mat])
            panelEntity.position = SIMD3(x: panel.x, y: panel.y, z: panel.z)
            panelEntity.name = "zone_panel_\(label)"
            zoneRoot.addChild(panelEntity)
        }

        // ── Label floating above the box ─────────────────────────────────
        let labelMesh = MeshResource.generatePlane(
            width: boxWidth - 0.02,
            height: 0.05,
            cornerRadius: 0.008
        )

        let labelView = ZoneLabelView(label: label, color: color)
        let renderer  = ImageRenderer(content: labelView)
        renderer.scale = 3.0
        renderer.proposedSize = .init(width: 300, height: 60)

        if let uiImage = renderer.uiImage,
           let cgImage = uiImage.cgImage,
           let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) {
            var labelMat = UnlitMaterial()
            labelMat.color = .init(texture: .init(texture))
            let labelEntity = ModelEntity(mesh: labelMesh, materials: [labelMat])
            // Float label just above the box opening
            labelEntity.position = SIMD3(x: 0, y: boxHeight + 0.04, z: 0)
            labelEntity.orientation = simd_quatf(angle: -.pi / 5, axis: SIMD3(1, 0, 0))
            zoneRoot.addChild(labelEntity)
        }

        return zoneRoot
    }
    
    /**
     * @brief highlights the zone card will go in
     */
    func updateZoneHighlight(zone: Entity, highlighted: Bool) {
        for child in zone.children {
            guard child.name.hasPrefix("zone_panel_"),
                  let panel = child as? ModelEntity
            else { continue }

            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: highlighted
                ? UIColor.white.withAlphaComponent(0.9)   // flash white on hover
                : (panel.model?.materials.first as? PhysicallyBasedMaterial)?
                    .baseColor.tint ?? UIColor.systemGray5
            )
            mat.roughness = .init(floatLiteral: 0.8)
            panel.model?.materials = [mat]
        }
    }
    
    /**
     * @ brief proximity direction
     * @return name of the nearest zone if within snap distance, else nil
     */
    func nearestZone(to position: SIMD3<Float>) -> String? {
        let snapDistance: Float = 0.18
        
        var nearest: String? = nil
        var nearestDist: Float = snapDistance
        
        for (name, zone) in appModel.categoryZones {
            // only compare XZ distance - zones are on a flat surface
            let zonePos = zone.position
            let dx = position.x - zonePos.x
            let dz = position.z - zonePos.z
            let dist = sqrt(dx * dx + dz * dz)
            
            if dist < nearestDist {
                nearestDist = dist
                nearest = name
            }
        }
        return nearest
    }
    
    /**
     * @brief snaps card to the category zone
     */
    func snapCard(entity: ModelEntity, cardID: UUID, toZone zoneName: String) {
        guard let zone = appModel.categoryZones[zoneName] else {return}
        
        // count how many cards are already in this zone for offset
        let existingCount = appModel.cards.values
            .filter { $0.groupID == UUID(uuidString: zoneName)}
            .count
        
        // stack cards with slight offset so they don't overlap
        let offsetX = Float(existingCount % 4) * 0.075 - 0.1
        let offsetZ = Float(existingCount / 4) * 0.075
        
        let snapPosition = SIMD3<Float>(
            zone.position.x + offsetX,
            zone.position.y + 0.08, // sit just above the plate surface
            zone.position.z + offsetZ
        )
        
        // smooth snap animation
        entity.move(
            to: Transform(
                scale: .one,
                rotation: simd_quatf(angle: -.pi / 2, axis: SIMD3(1,0,0)), // lay flat
                translation: snapPosition
            ),
            relativeTo: nil,
            duration: 0.25
        )
        
        // update AppModel
        appModel.cards[cardID]?.transform = CodableTransform(entity.transform.matrix)
        appModel.cards[cardID]?.groupID = UUID(uuidString: zoneName)
        
        // broadcast to other headset
        sessionManager.send(.objectMoved(
            id: cardID,
            transform: CodableTransform(entity.transform.matrix)
        ))
    }
    
    /**
     * @brief spawns the emoji entity
     */
    func spawnReaction(gesture: ReactionGesture, at position: SIMD3<Float>) {
        let labelView = ReactionView(emoji: gesture.emoji)
        let renderer = ImageRenderer(content: labelView)
        renderer.scale = 3.0
        renderer.proposedSize = .init(width: 120, height: 120)
        
        guard let uiImage = renderer.uiImage,
              let cgImage = uiImage.cgImage,
              let texture = try? TextureResource(
                image: cgImage, options: .init(semantic: .color))
        else {return}
        
        var mat = UnlitMaterial()
        mat.color = .init(texture: .init(texture))
        
        let mesh = MeshResource.generatePlane(width: 0.12, height: 0.12, cornerRadius: 0.06)
        let entity = ModelEntity(mesh: mesh, materials: [mat])
        
        // spawn just above the hand
        entity.position = position + SIMD3(0, 0.15, 0)
        
        // billboard - always face the user
        entity.components.set(BillboardComponent())
        
        // add to scene
        // access content via AppModel root entity or a dedicated reactions anchor
        appModel.reactionAnchor?.addChild(entity)
        
        // animate: float up and fade out over 1.5 seconds
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            entity.move(
                to: Transform(translation: entity.position + SIMD3(0,0.2,0)),
                relativeTo: nil,
                duration: 1.5
            )
            try? await Task.sleep(for: .seconds(1.5))
            entity.removeFromParent()
        }
    }
    
    
    /* Card Facing view */
    struct CardFaceView : View {
        let label: String
        let color: UIColor
        
        var body: some View {
            ZStack {
                // Card background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(color))
                
                // small border
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                
                // label text
                Text(label)
                    .font(.headline)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
            .frame(width:200, height: 300)
        }
    }
    
    struct ZoneLabelView: View {
        let label: String
        let color: UIColor
        
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(color).opacity(0.85))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(color), lineWidth: 2)
                Text(label)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 1)
            }
            .frame(width:300, height: 60)
        }
    }
    
    struct ReactionView: View {
        let emoji: String
        var body: some View {
            Text(emoji)
                .font(.system(size: 72))
                .frame(width: 120, height: 120)
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
        .environment(SessionManager())
}
