import Foundation

/// Errors specific to PLY parsing.
enum PLYParserError: LocalizedError {
    case fileNotFound(String)
    case invalidHeader
    case unsupportedFormat
    case unexpectedEOF
    case missingVertexElement

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "PLY file not found: \(path)"
        case .invalidHeader: return "Could not parse PLY header"
        case .unsupportedFormat: return "Only binary_little_endian PLY is supported"
        case .unexpectedEOF: return "Unexpected end of file while reading vertex data"
        case .missingVertexElement: return "PLY has no vertex element"
        }
    }
}

/// Parses binary little-endian PLY files produced by SHARP.
///
/// Expected vertex layout (14 floats, 56 bytes each):
///   x, y, z, f_dc_0, f_dc_1, f_dc_2, opacity,
///   scale_0, scale_1, scale_2, rot_0, rot_1, rot_2, rot_3
///
/// Additional elements (extrinsic, intrinsic, etc.) are skipped.
enum PLYParser {

    // MARK: - Header types

    private struct ElementDescriptor {
        let name: String
        let count: Int
        let bytesPerEntry: Int
    }

    /// Property sizes in bytes for binary PLY.
    private static func propertySize(_ typeName: String) -> Int {
        switch typeName {
        case "float", "float32", "int", "int32", "uint", "uint32":
            return 4
        case "double", "float64", "int64", "uint64":
            return 8
        case "uchar", "uint8", "char", "int8":
            return 1
        case "short", "int16", "ushort", "uint16":
            return 2
        default:
            return 4 // assume float-sized
        }
    }

    // MARK: - Public API

    /// Parse a PLY file at `url` into a `GaussianCloud`. Runs synchronously
    /// (call from a background thread).
    static func parse(url: URL) throws -> GaussianCloud {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PLYParserError.fileNotFound(url.path)
        }

        // Memory-map the file for performance on large files.
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        // --- Parse header ---------------------------------------------------

        guard let headerEndRange = data.range(of: Data("end_header\n".utf8)) else {
            throw PLYParserError.invalidHeader
        }
        let headerBytes = data[data.startIndex..<headerEndRange.upperBound]
        guard let headerString = String(data: headerBytes, encoding: .ascii) else {
            throw PLYParserError.invalidHeader
        }

        let lines = headerString.components(separatedBy: "\n")

        // Verify format
        guard lines.contains(where: { $0.hasPrefix("format binary_little_endian") }) else {
            throw PLYParserError.unsupportedFormat
        }

        // Walk header lines and build element descriptors in order.
        var elements: [ElementDescriptor] = []
        var currentName: String?
        var currentCount: Int = 0
        var currentBytes: Int = 0

        for line in lines {
            let parts = line.split(separator: " ")
            if parts.first == "element", parts.count >= 3,
               let count = Int(parts[2]) {
                // Flush previous element.
                if let name = currentName {
                    elements.append(ElementDescriptor(name: name, count: count > 0 ? currentCount : 0, bytesPerEntry: currentBytes))
                }
                currentName = String(parts[1])
                currentCount = count
                currentBytes = 0
            } else if parts.first == "property", parts.count >= 3 {
                // Skip list properties (not expected in SHARP output).
                if parts[1] == "list" { continue }
                let typeName = String(parts[1])
                currentBytes += propertySize(typeName)
            }
        }
        // Flush last element.
        if let name = currentName {
            elements.append(ElementDescriptor(name: name, count: currentCount, bytesPerEntry: currentBytes))
        }

        // Find the vertex element.
        guard let vertexElement = elements.first(where: { $0.name == "vertex" }) else {
            throw PLYParserError.missingVertexElement
        }

        let vertexCount = vertexElement.count
        let bytesPerVertex = vertexElement.bytesPerEntry // expected: 56

        // Compute byte offset to vertex data — it's right after the header.
        // But we also need to skip elements that come *before* vertex in the header
        // (none in SHARP's output — vertex is first).
        var dataOffset = headerEndRange.upperBound
        for elem in elements {
            if elem.name == "vertex" { break }
            dataOffset += elem.count * elem.bytesPerEntry
        }

        let vertexDataEnd = dataOffset + vertexCount * bytesPerVertex
        guard data.count >= vertexDataEnd else {
            throw PLYParserError.unexpectedEOF
        }

        // --- Read vertex data ------------------------------------------------

        var positions = [SIMD3<Float>]()
        var colors = [SIMD4<Float>]()
        positions.reserveCapacity(vertexCount)
        colors.reserveCapacity(vertexCount)

        data.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.baseAddress!
            for i in 0..<vertexCount {
                let ptr = (base + dataOffset + i * bytesPerVertex)
                    .assumingMemoryBound(to: Float.self)

                let x = ptr[0]
                let y = ptr[1]
                let z = ptr[2]

                let shR = ptr[3]  // f_dc_0
                let shG = ptr[4]  // f_dc_1
                let shB = ptr[5]  // f_dc_2
                let rawOpacity = ptr[6]

                let rgb = shToRGB(shR, shG, shB)
                let alpha = sigmoid(rawOpacity)

                positions.append(SIMD3<Float>(x, y, z))
                colors.append(SIMD4<Float>(rgb.x, rgb.y, rgb.z, alpha))
            }
        }

        return GaussianCloud(positions: positions, colors: colors)
    }
}
