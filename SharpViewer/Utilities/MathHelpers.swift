import Foundation
import simd

/// Sigmoid activation: 1 / (1 + exp(-x))
func sigmoid(_ x: Float) -> Float {
    1.0 / (1.0 + exp(-x))
}

/// Convert zeroth-order spherical harmonic coefficient to RGB color.
/// SH_0 basis = 0.28209479177387814
/// color = SH_coeff * SH_0 + 0.5, clamped to [0, 1]
func shToRGB(_ shR: Float, _ shG: Float, _ shB: Float) -> SIMD3<Float> {
    let sh0: Float = 0.28209479177387814
    let r = clamp01(shR * sh0 + 0.5)
    let g = clamp01(shG * sh0 + 0.5)
    let b = clamp01(shB * sh0 + 0.5)
    return SIMD3<Float>(r, g, b)
}

/// Clamp a value to [0, 1].
func clamp01(_ x: Float) -> Float {
    min(max(x, 0), 1)
}
