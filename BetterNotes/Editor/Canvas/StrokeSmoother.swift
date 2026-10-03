import PencilKit

/// Stabilizzazione del tratto: filtro gaussiano calcolato sulla distanza percorsa lungo il tratto
/// (non sul numero di punti), così elimina il tremolio della mano senza deformare lettere e angoli.
/// Le estremità restano fisse, così il tratto inizia e finisce dove l'ha posato la Pencil.
enum StrokeSmoother {
    /// Deviazione standard massima (in punti tela) con stabilizzazione al 100%.
    private static let maxSigma: Double = 4.5

    static func smooth(_ stroke: PKStroke, amount: Double) -> PKStroke {
        let points = Array(stroke.path)
        let count = points.count
        guard count > 3, amount > 0.01 else { return stroke }

        // Lunghezza cumulativa lungo il tratto.
        var arc = [Double](repeating: 0, count: count)
        for index in 1..<count {
            let a = points[index - 1].location, b = points[index].location
            arc[index] = arc[index - 1] + Double(hypot(b.x - a.x, b.y - a.y))
        }
        let total = arc[count - 1]
        guard total > 1 else { return stroke }

        let baseSigma = maxSigma * amount
        var result: [PKStrokePoint] = []
        result.reserveCapacity(count)

        for index in 0..<count {
            let point = points[index]
            // Vicino alle estremità il filtro si restringe fino a zero.
            let sigma = min(baseSigma, arc[index] / 2.5, (total - arc[index]) / 2.5)
            guard sigma > 0.05 else {
                result.append(point)
                continue
            }
            let reach = sigma * 3
            var sumX = 0.0, sumY = 0.0, weightSum = 0.0
            var j = index
            while j >= 0, arc[index] - arc[j] <= reach {
                let d = arc[index] - arc[j]
                let w = exp(-(d * d) / (2 * sigma * sigma))
                sumX += Double(points[j].location.x) * w
                sumY += Double(points[j].location.y) * w
                weightSum += w
                j -= 1
            }
            j = index + 1
            while j < count, arc[j] - arc[index] <= reach {
                let d = arc[j] - arc[index]
                let w = exp(-(d * d) / (2 * sigma * sigma))
                sumX += Double(points[j].location.x) * w
                sumY += Double(points[j].location.y) * w
                weightSum += w
                j += 1
            }
            let location = CGPoint(x: sumX / weightSum, y: sumY / weightSum)
            result.append(PKStrokePoint(
                location: location,
                timeOffset: point.timeOffset,
                size: point.size,
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale,
                threshold: point.threshold
            ))
        }

        let path = PKStrokePath(controlPoints: result, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
