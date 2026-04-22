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
    
    //@State private var cardEntity: ModelEntity? = nil

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)

                // Skybox Implementation
                guard let skyBox = generateSkyBox() else { return }
                content.add(skyBox)
                
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
                    card.position = SIMD3(x: Float(index) * 0.15 - 0.3, y: 1.5, z: -0.6)
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
                    sessionManager.send(.objectMoved(
                        id: cardID,
                        transform: CodableTransform(entity.transform.matrix)
                    ))
                }
        )
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
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
        .environment(SessionManager())
}
