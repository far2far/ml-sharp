import SwiftUI

/// Root view: HSplitView with image drop zone on the left, 3D viewer on the right,
/// and a status bar at the bottom.
struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ImageDropZone()
                    .frame(minWidth: 250, idealWidth: 350)

                pointCloudPanel
                    .frame(minWidth: 300, idealWidth: 500)
            }

            Divider()

            StatusBar()
        }
    }

    @ViewBuilder
    private var pointCloudPanel: some View {
        if let cloud = state.cloud {
            PointCloudView(cloud: cloud)
        } else {
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("3D point cloud will appear here")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}
