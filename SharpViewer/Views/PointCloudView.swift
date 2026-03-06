import SwiftUI
import SceneKit

/// Right panel: renders a `GaussianCloud` as a colored point cloud in SceneKit.
struct PointCloudView: NSViewRepresentable {
    let cloud: GaussianCloud?

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = SCNScene()
        scnView.allowsCameraControl = true      // orbit + zoom with mouse
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .black

        // Default camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 1000
        cameraNode.position = SCNVector3(0, 0, 3)
        scnView.scene?.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        context.coordinator.scnView = scnView

        if let cloud {
            context.coordinator.updateCloud(cloud)
        }

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.updateCloud(cloud)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator {
        weak var scnView: SCNView?
        private var currentCloudID: Int = 0  // cheap identity check

        func updateCloud(_ cloud: GaussianCloud?) {
            guard let cloud, let scene = scnView?.scene else {
                // Remove old geometry
                scnView?.scene?.rootNode.childNodes
                    .filter { $0.name == "cloud" }
                    .forEach { $0.removeFromParentNode() }
                currentCloudID = 0
                return
            }

            let newID = cloud.count
            guard newID != currentCloudID else { return }
            currentCloudID = newID

            // Remove old cloud node.
            scene.rootNode.childNodes
                .filter { $0.name == "cloud" }
                .forEach { $0.removeFromParentNode() }

            // Build geometry on a background thread, attach on main.
            let positions = cloud.positions
            let colors = cloud.colors
            DispatchQueue.global(qos: .userInitiated).async {
                let geometry = Self.makePointGeometry(positions: positions, colors: colors)
                DispatchQueue.main.async {
                    let node = SCNNode(geometry: geometry)
                    node.name = "cloud"
                    // Flip Y: OpenCV (y-down) → SceneKit (y-up)
                    node.eulerAngles.x = .pi
                    scene.rootNode.addChildNode(node)
                }
            }
        }

        // MARK: - Geometry builder

        private static func makePointGeometry(
            positions: [SIMD3<Float>],
            colors: [SIMD4<Float>]
        ) -> SCNGeometry {
            let count = positions.count

            // Vertex positions
            let posData = positions.withUnsafeBufferPointer { buf in
                Data(bytes: buf.baseAddress!, count: count * MemoryLayout<SIMD3<Float>>.stride)
            }
            let posSource = SCNGeometrySource(
                data: posData,
                semantic: .vertex,
                vectorCount: count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            )

            // Vertex colors (RGBA float)
            let colData = colors.withUnsafeBufferPointer { buf in
                Data(bytes: buf.baseAddress!, count: count * MemoryLayout<SIMD4<Float>>.stride)
            }
            let colSource = SCNGeometrySource(
                data: colData,
                semantic: .color,
                vectorCount: count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD4<Float>>.stride
            )

            // Point primitive — one index per vertex.
            var indices = [UInt32]()
            indices.reserveCapacity(count)
            for i in 0..<UInt32(count) {
                indices.append(i)
            }
            let indexData = indices.withUnsafeBufferPointer { buf in
                Data(bytes: buf.baseAddress!, count: count * MemoryLayout<UInt32>.size)
            }
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .point,
                primitiveCount: count,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            element.pointSize = 2
            element.minimumPointScreenSpaceRadius = 1
            element.maximumPointScreenSpaceRadius = 5

            let geometry = SCNGeometry(sources: [posSource, colSource], elements: [element])

            // Unlit material — show vertex colors directly.
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor.white
            geometry.materials = [material]

            return geometry
        }
    }
}
