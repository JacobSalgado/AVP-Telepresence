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
        RealityView { content, attachments in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
            
                if let whiteboard = attachments.entity(for: "whiteboard") {
                    whiteboard.name = "whiteboard"
                    whiteboard.position = [0, 1.3, -1.2]
                    whiteboard.scale = .one * 1.4
                    content.add(whiteboard)
                }

                // Skybox Implementation
                guard let skyBox = generateSkyBox() else { return }
                content.add(skyBox)

                }
            }
        
        update: { content, attachments in
            // fill code here for Swiftui changes
            // called whenever AppModel Changes
            // Applies any incoming remote updates to local entities
            // jigsaw piece entities will go here
        }
        attachments: {
            Attachment(id: "whiteboard") {
                WhiteboardView()
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged{ value in
                    // move entities
                    guard value.entity.name == "whiteboard" else {return}
                    
                    let newPosition = value.convert(
                        value.gestureValue.location3D,
                        from: .local,
                        to: .scene
                    )
                    value.entity.position = newPosition
                }
        )
        .simultaneousGesture(
            RotateGesture3D()
                .targetedToAnyEntity()
                .onChanged { value in
                    let entity = value.entity
                    entity.orientation = simd_quatf(value.rotation) * entity.orientation
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
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
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
        .environment(SessionManager())
}
