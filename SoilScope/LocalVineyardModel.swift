import CoreImage
import Foundation
import UIKit

// On-device implementation of the four features used by the Field F Ridge fit.
// Coefficients are frozen from test_expanded_calibration.py's six TRAIN rows.
enum LocalVineyardModel {
    struct Result {
        let moisture: Double
        let warnings: [String]
    }

    enum ModelError: LocalizedError {
        case unusableSelection
        case insufficientNearSoil
        case invalidPrediction

        var errorDescription: String? {
            switch self {
            case .unusableSelection: "The selected four points do not make a usable image region."
            case .insufficientNearSoil: "Not enough visible soil close to plants. Include a plant and nearby ground."
            case .invalidPrediction: "The local model could not produce a valid moisture estimate."
            }
        }
    }

    private static let side = 512
    private static let mean = [0.5673202614379086, 0.17447795766470153,
                               0.037816505112366575, 5.18436218037851]
    private static let scale = [0.05974108869911385, 0.020111304083061096,
                                0.005489494135172548, 0.11070431384471266]
    private static let weight = [0.5172020388944617, -0.9124260584733543,
                                 0.4095143965922559, 0.9473744328211132]
    private static let intercept = 23.82333333333334

    static func predict(photo: UIImage, points: [CGPoint],
                        physicalSizeM: CGSize, nadirDeviationDegrees: Double) throws -> Result {
        guard points.count == 4 else { throw ModelError.unusableSelection }
        let widthM = Double(physicalSizeM.width)
        let heightM = Double(physicalSizeM.height)
        guard widthM.isFinite, heightM.isFinite, widthM > 0, heightM > 0 else {
            throw ModelError.unusableSelection
        }
        let rgba = try rectifiedPixels(photo: photo, points: points)
        let count = side * side
        var red = [Double](repeating: 0, count: count)
        var green = red
        var blue = red
        var rawPlant = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            let offset = index * 4
            let r = Double(rgba[offset]) / 255
            let g = Double(rgba[offset + 1]) / 255
            let b = Double(rgba[offset + 2]) / 255
            red[index] = r
            green[index] = g
            blue[index] = b
            if 2*g-r-b > 0.05 && g > r*1.02 && g > b*1.02 { rawPlant[index] = 1 }
        }

        // Match the training extractor's 5×5 operators at 2 m; scale their
        // approximate physical footprint for other selections.
        let radiusX = Int(min(4.0, max(1.0, 4.0 / widthM)).rounded())
        let radiusY = Int(min(4.0, max(1.0, 4.0 / heightM)).rounded())
        let opened = dilate(erode(rawPlant, radiusX: radiusX, radiusY: radiusY),
                            radiusX: radiusX, radiusY: radiusY)
        let closed = erode(dilate(opened, radiusX: radiusX, radiusY: radiusY),
                           radiusX: radiusX, radiusY: radiusY)
        let plant = dilate(closed, radiusX: radiusX, radiusY: radiusY)
        let plantFraction = Double(plant.reduce(0) { $0 + Int($1) }) / Double(count)
        let distance = distanceFromPlants(plant, widthM: widthM, heightM: heightM)
        // Original 3–30 pixel band at 512 px across a 2 m training crop.
        let nearMinimumM = 3.0 * 2.0 / Double(side)
        let nearMaximumM = 30.0 * 2.0 / Double(side)
        var values = [Double]()
        var exg = [Double]()
        var grayscale = [UInt8](repeating: 0, count: count)
        var valid = [UInt8](repeating: 0, count: count)
        values.reserveCapacity(count / 4)
        exg.reserveCapacity(count / 4)
        for index in 0..<count {
            if plant[index] == 0 && distance[index] > nearMinimumM && distance[index] <= nearMaximumM {
                valid[index] = 1
                values.append((red[index] + green[index] + blue[index]) / 3)
                exg.append(2*green[index] - red[index] - blue[index])
                grayscale[index] = UInt8(clamping: Int((0.299*red[index] + 0.587*green[index]
                                                      + 0.114*blue[index])*255 + 0.5))
            }
        }
        guard values.count >= 250 else { throw ModelError.insufficientNearSoil }
        let medianIntensity = quantile(values.sorted(), 0.5)
        let average = values.reduce(0, +) / Double(values.count)
        let intensityStd = sqrt(values.reduce(0) { $0 + ($1-average)*($1-average) } / Double(values.count))
        let averageExg = exg.reduce(0, +) / Double(exg.count)
        let entropy = glcmEntropy(gray: grayscale, valid: valid,
                                  stepX: Int(min(16.0, max(1.0, 2.0 / widthM)).rounded()),
                                  stepY: Int(min(16.0, max(1.0, 2.0 / heightM)).rounded()))
        let feature = [medianIntensity, intensityStd, averageExg, entropy]
        let moisture = intercept + zip(feature.indices, feature).reduce(0) { total, element in
            total + weight[element.0] * (element.1 - mean[element.0]) / scale[element.0]
        }
        guard moisture.isFinite, (0...80).contains(moisture) else { throw ModelError.invalidPrediction }
        var warnings = [
            "Research-only: this Field F model was trained on six drone crops, not iPhone photos.",
            "Earlier Field F test-image alignment was questioned; its exploratory MAE is not phone accuracy."
        ]
        if !(1.6...2.4).contains(widthM) || !(1.6...2.4).contains(heightM) {
            warnings.append(String(format: "Selected area is %.2f × %.2f m; the model was fitted on ~2 × 2 m crops. Scale-adjusted features are exploratory.", widthM, heightM))
        }
        if nadirDeviationDegrees > 25 {
            warnings.append("Oblique view exceeds the training-like camera angle; perspective and LiDAR scale may be inaccurate.")
        }
        if !(0.20...0.55).contains(plantFraction) {
            warnings.append("Plant cover differs from the training images; check that the plant is centered.")
        }
        return Result(moisture: moisture, warnings: warnings)
    }

    private static func rectifiedPixels(photo: UIImage, points: [CGPoint]) throws -> [UInt8] {
        guard let cgImage = photo.cgImage else { throw ModelError.unusableSelection }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let xy = points.map { CGPoint(x: $0.x * width, y: $0.y * height) }
        let area = abs(zip(0..<4, xy).reduce(CGFloat.zero) { sum, item in
            let next = xy[(item.0 + 1) % 4]
            return sum + item.1.x * next.y - next.x * item.1.y
        }) / 2
        guard area > 40_000, points.allSatisfy({ (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw ModelError.unusableSelection
        }
        // CI uses a lower-left origin; the UI's points use an upper-left origin.
        let image = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: xy[0].x, y: height - xy[0].y), forKey: "inputTopLeft")
        filter.setValue(CIVector(x: xy[1].x, y: height - xy[1].y), forKey: "inputTopRight")
        filter.setValue(CIVector(x: xy[2].x, y: height - xy[2].y), forKey: "inputBottomRight")
        filter.setValue(CIVector(x: xy[3].x, y: height - xy[3].y), forKey: "inputBottomLeft")
        guard let output = filter.outputImage, output.extent.width > 0, output.extent.height > 0 else {
            throw ModelError.unusableSelection
        }
        let normalized = output.transformed(by: CGAffineTransform(translationX: -output.extent.minX,
                                                                 y: -output.extent.minY))
        let resized = normalized.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / output.extent.width,
                                                                  y: CGFloat(side) / output.extent.height))
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
        bytes.withUnsafeMutableBytes { buffer in
            ciContext.render(resized, toBitmap: buffer.baseAddress!, rowBytes: side * 4,
                             bounds: CGRect(x: 0, y: 0, width: side, height: side),
                             format: .RGBA8, colorSpace: colorSpace)
        }
        return bytes
    }

    private static func erode(_ image: [UInt8], radiusX: Int, radiusY: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.count)
        for y in 0..<side { for x in 0..<side {
            var keep: UInt8 = 1
            for dy in -radiusY...radiusY {
                let yy = y + dy
                if yy < 0 || yy >= side { continue }
                for dx in -radiusX...radiusX {
                    let xx = x + dx
                    if xx >= 0 && xx < side && image[yy * side + xx] == 0 { keep = 0; break }
                }
                if keep == 0 { break }
            }
            result[y * side + x] = keep
        }}
        return result
    }

    private static func dilate(_ image: [UInt8], radiusX: Int, radiusY: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.count)
        for y in 0..<side { for x in 0..<side {
            var hit: UInt8 = 0
            for dy in -radiusY...radiusY {
                let yy = y + dy
                if yy < 0 || yy >= side { continue }
                for dx in -radiusX...radiusX {
                    let xx = x + dx
                    if xx >= 0 && xx < side && image[yy * side + xx] != 0 { hit = 1; break }
                }
                if hit == 1 { break }
            }
            result[y * side + x] = hit
        }}
        return result
    }

    private static func distanceFromPlants(_ plant: [UInt8], widthM: Double,
                                           heightM: Double) -> [Double] {
        // Approximate metric distance to canopy, independent of the selected area size.
        let horizontal = widthM / Double(side)
        let vertical = heightM / Double(side)
        let diagonal = hypot(horizontal, vertical)
        var distance = plant.map { $0 == 1 ? 0.0 : Double.infinity }
        for y in 0..<side { for x in 0..<side {
            let i = y * side + x
            if x > 0 { distance[i] = min(distance[i], distance[i-1] + horizontal) }
            if y > 0 { distance[i] = min(distance[i], distance[i-side] + vertical) }
            if x > 0 && y > 0 { distance[i] = min(distance[i], distance[i-side-1] + diagonal) }
            if x+1 < side && y > 0 { distance[i] = min(distance[i], distance[i-side+1] + diagonal) }
        }}
        for y in (0..<side).reversed() { for x in (0..<side).reversed() {
            let i = y * side + x
            if x+1 < side { distance[i] = min(distance[i], distance[i+1] + horizontal) }
            if y+1 < side { distance[i] = min(distance[i], distance[i+side] + vertical) }
            if x+1 < side && y+1 < side { distance[i] = min(distance[i], distance[i+side+1] + diagonal) }
            if x > 0 && y+1 < side { distance[i] = min(distance[i], distance[i+side-1] + diagonal) }
        }}
        return distance
    }

    private static func quantile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p * Double(sorted.count - 1)
        let lower = Int(position)
        let upper = min(sorted.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    private static func glcmEntropy(gray: [UInt8], valid: [UInt8],
                                    stepX: Int, stepY: Int) -> Double {
        let samples = gray.indices.filter { valid[$0] != 0 }.map { Double(gray[$0]) }.sorted()
        let thresholds = (1...7).map { quantile(samples, Double($0) / 8) }
        var level = [Int](repeating: 0, count: gray.count)
        for index in gray.indices where valid[index] != 0 {
            level[index] = thresholds.reduce(0) { $0 + (Double(gray[index]) >= $1 ? 1 : 0) }
        }
        var matrix = [Double](repeating: 0, count: 64)
        let directions = [(0, stepX), (stepY, 0), (stepY, stepX), (stepY, -stepX)]
        for y in 0..<side { for x in 0..<side {
            let a = y * side + x
            if valid[a] == 0 { continue }
            for (dy, dx) in directions {
                let yy = y + dy, xx = x + dx
                if yy < 0 || yy >= side || xx < 0 || xx >= side { continue }
                let b = yy * side + xx
                if valid[b] == 0 { continue }
                matrix[level[a] * 8 + level[b]] += 1
                matrix[level[b] * 8 + level[a]] += 1
            }
        }}
        let total = matrix.reduce(0, +)
        guard total > 0 else { return 0 }
        return -matrix.reduce(0) { entropy, count in
            if count == 0 { return entropy }
            let probability = count / total
            return entropy + probability * log2(probability)
        }
    }
}
