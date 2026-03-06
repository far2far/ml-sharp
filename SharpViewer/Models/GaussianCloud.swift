import Foundation
import simd

/// Parsed Gaussian splat point cloud — positions and vertex colors.
struct GaussianCloud {
    /// World-space positions for each Gaussian center.
    let positions: [SIMD3<Float>]
    /// RGBA colors (SH→RGB + sigmoid opacity) per vertex.
    let colors: [SIMD4<Float>]

    var count: Int { positions.count }
}
