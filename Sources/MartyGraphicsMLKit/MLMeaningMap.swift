// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

struct MLMeaningMap: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        let label: String
        let position: [Double]
        let image: MLPixels?
    }

    struct Neighbor: Equatable, Sendable {
        let from: Int
        let to: Int
        let value: Double
    }

    let points: [Point]
    let citation: String?
    let dimension: Int
    let neighbors: [Neighbor]
    let cluster: Set<String>

    var label: String {
        dimension == 2 ? "illustrative positions" : "2D projection (PCA) of the given vectors"
    }

    init(_ input: MLObject) throws {
        let explicit = input.values["points"] != nil
        guard explicit != (input.values["vectors"] != nil) else { throw input.issue(.mapCoordinates, "points") }
        let key = explicit ? "points" : "vectors"
        let coordinate = explicit ? "position" : "vector"
        guard case .array(let entries)? = input.values[key], (3...12).contains(entries.count) else {
            throw input.issue(.mapCount, key)
        }
        var labels: [String] = []
        var vectors: [[Double]] = []
        var images: [MLPixels?] = []
        var seen = Set<String>()
        let imageReason = MGMLReason.picturePNG
        for (index, entry) in entries.enumerated() {
            let point = try MLObject(entry, path: "\(input.path).\(key)[\(index)]", keys: ["label", coordinate, "imagePNG"])
            let label = try point.text("label", max: 16, reason: .mapCoordinates)
            guard seen.insert(label).inserted else { throw point.issue(.mapDuplicate, "label") }
            labels.append(label)
            guard case .array(let numbers)? = point.values[coordinate],
                  (explicit ? 2...2 : 3...32).contains(numbers.count),
                  vectors.first.map({ $0.count == numbers.count }) ?? true else {
                throw point.issue(.mapLengths, coordinate)
            }
            vectors.append(try numbers.enumerated().map { index, value in
                guard case .number(let number) = value, number.isFinite, abs(number) <= 1e12 else {
                    throw point.issue(.mapCoordinates, "\(coordinate)[\(index)]")
                }
                return number
            })
            images.append(try point.values["imagePNG"].map {
                try MLPixels($0, invalid: point.issue(imageReason, "imagePNG"), size: point.issue(.pictureSize, "imagePNG"))
            })
        }
        let citation = try input.optionalText("vectorCitation", max: 120, reason: .mapCoordinates)
        guard citation == nil || !explicit else { throw input.issue(.mapCoordinates, "vectorCitation") }
        self.citation = citation
        self.dimension = vectors[0].count

        let positions = explicit ? vectors : try Self.project(vectors, issue: input.issue(.mapCoordinates, key))
        points = labels.indices.map { Point(label: labels[$0], position: positions[$0], image: images[$0]) }

        var links: [Neighbor] = []
        if let setting = input.values["nearestNeighbors"] {
            guard case .bool(let enabled) = setting else { throw input.issue(.mapCosine, "nearestNeighbors") }
            if enabled {
                links = explicit ? Self.nearestPoints(positions)
                    : try Self.nearestVectors(vectors, issue: input.issue(.mapCosine, key))
            }
        }
        neighbors = links

        if case .array(let raw)? = input.values["cluster"] {
            let selected = raw.compactMap { value -> String? in
                if case .string(let word) = value, seen.contains(word) { return word }
                return nil
            }
            cluster = Set(selected)
            guard !cluster.isEmpty, cluster.count == raw.count else { throw input.issue(.mapCluster, "cluster") }
        } else {
            guard input.values["cluster"] == nil else { throw input.issue(.mapCluster, "cluster") }
            cluster = []
        }
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func nearestPoints(_ positions: [[Double]]) -> [Neighbor] {
        positions.indices.map { from in
            let point = positions[from]
            var best = Neighbor(from: from, to: from, value: .infinity)
            for to in positions.indices where to != from {
                let distance = hypot(point[0] - positions[to][0], point[1] - positions[to][1])
                if distance < best.value {
                    best = Neighbor(from: from, to: to, value: distance)
                }
            }
            return best
        }
    }

    private static func nearestVectors(_ vectors: [[Double]], issue: MGMLIssue) throws -> [Neighbor] {
        let normalized = try vectors.map { vector in
            guard let scale = vector.map(abs).max(), scale > 0 else { throw issue }
            let scaled = vector.map { $0 / scale }
            let norm = sqrt(dot(scaled, scaled))
            return scaled.map { $0 / norm }
        }
        return normalized.indices.compactMap { from in
            var best: Neighbor?
            for to in normalized.indices where from != to {
                let cosine = max(-1, min(1, dot(normalized[from], normalized[to])))
                guard cosine > 0 else { continue }
                if best.map({ cosine > $0.value }) ?? true {
                    best = Neighbor(from: from, to: to, value: cosine)
                }
            }
            return best
        }
    }

    /// Diagonalize the centered Gram matrix with cyclic Jacobi rotations. Its dimension
    /// is the point count, and its two largest eigenpairs give the PCA scores.
    private static func project(_ vectors: [[Double]], issue: MGMLIssue) throws -> [[Double]] {
        let count = vectors.count, dimensions = vectors[0].count
        let scale = vectors.lazy.flatMap { $0 }.map(abs).max() ?? 0
        guard scale > 0 else { return Array(repeating: [0, 0], count: count) }
        let scaled = vectors.map { $0.map { $0 / scale } }
        let means = (0..<dimensions).map { column in scaled.reduce(0) { $0 + $1[column] } / Double(count) }
        let centered = scaled.map { row in zip(row, means).map { $0.0 - $0.1 } }
        let gram = centered.map { row in centered.map { dot(row, $0) } }
        var matrix = gram
        var basis = (0..<count).map { row in (0..<count).map { row == $0 ? 1.0 : 0 } }
        let energy = (0..<count).reduce(0) { $0 + gram[$1][$1] }
        let epsilon = energy * 1e-14
        for _ in 0..<40 {
            var rotated = false
            for p in 0..<count - 1 {
                for q in p + 1..<count {
                    let off = matrix[p][q]
                    guard abs(off) > epsilon else { continue }
                    rotated = true
                    let tau = (matrix[q][q] - matrix[p][p]) / (2 * off)
                    let tangent = (tau < 0 ? -1.0 : 1.0) / (abs(tau) + hypot(1, tau))
                    let c = 1 / sqrt(1 + tangent * tangent), s = tangent * c
                    matrix[p][p] -= tangent * off
                    matrix[q][q] += tangent * off
                    matrix[p][q] = 0
                    matrix[q][p] = 0
                    for i in 0..<count {
                        if i != p, i != q {
                            let left = matrix[i][p], right = matrix[i][q]
                            matrix[i][p] = c * left - s * right
                            matrix[i][q] = s * left + c * right
                            matrix[p][i] = matrix[i][p]
                            matrix[q][i] = matrix[i][q]
                        }
                        let left = basis[i][p], right = basis[i][q]
                        basis[i][p] = c * left - s * right
                        basis[i][q] = s * left + c * right
                    }
                }
            }
            if !rotated { break }
        }

        let leading = (0..<count).sorted { left, right in
            let leftEigenvalue = matrix[left][left]
            let rightEigenvalue = matrix[right][right]
            return leftEigenvalue == rightEigenvalue ? left < right : leftEigenvalue > rightEigenvalue
        }.prefix(2)
        let axes: [[Double]] = try leading.map { column in
            let eigenvalue = matrix[column][column]
            guard eigenvalue > epsilon else { return Array(repeating: 0, count: count) }
            let eigenvector = basis.map { $0[column] }
            let residual = gram.indices.map { abs(dot(gram[$0], eigenvector) - eigenvalue * eigenvector[$0]) }
            guard residual.allSatisfy({ $0 <= energy * 1e-10 }) else { throw issue }
            let loadings = (0..<dimensions).map { j in dot(centered.map { $0[j] }, eigenvector) }
            let largest = loadings.reduce(0) { abs($1) > abs($0) ? $1 : $0 }
            let magnitude = sqrt(eigenvalue) * (largest < 0 ? -scale : scale)
            return eigenvector.map { $0 * magnitude }
        }
        let positions = zip(axes[0], axes[1]).map { [$0.0, $0.1] }
        guard positions.joined().allSatisfy(\.isFinite) else { throw issue }
        return positions
    }

    var facts: [String: MGJSON] {
        [
            "label": .string(label), "vectorDimension": .number(Double(dimension)),
            "vectorCitation": citation.map(MGJSON.string) ?? .null,
            "points": .array(points.map {
                .object(["label": .string($0.label), "position": .array($0.position.map(MGJSON.number)),
                         "imageMarker": .bool($0.image != nil)])
            }),
            "cluster": .array(points.filter { cluster.contains($0.label) }.map { .string($0.label) }),
            "nearestNeighbors": .array(neighbors.map {
                .object(["from": .string(points[$0.from].label), "to": .string(points[$0.to].label),
                         (dimension == 2 ? "distance" : "cosine"): .number($0.value)])
            })
        ]
    }
}
