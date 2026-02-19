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

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)

                // Skybox Implementation
                guard let skyBox = generateSkyBox() else { return }
                
                content.add(skyBox)
            }
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
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
