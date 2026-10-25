import ARKit
import CoreImage
import SwiftUI

@MainActor
final class ScanModel: ObservableObject {
    @Published var photo: UIImage?
    @Published var points: [CGPoint] = [] // Normalized image coordinates, TL/TR/BR/BL.
    @Published var distanceM: Double?
    @Published var usesManualScale = false
    @Published var manualReferencePoints: [CGPoint] = [] // Two points on known ground length.
    @Published var manualReferenceLengthCM = "" {
        didSet {
            guard manualReferenceLengthCM != oldValue else { return }
            moistureVWC = nil
            modelWarnings = []
        }
    }
    @Published var nadirDeviationDegrees: Double?
    @Published var moistureVWC: Double?
    @Published var modelWarnings: [String] = []
    @Published var status = "Frame the plant and nearby soil."
    @Published var isPredicting = false
    @Published var isLiDARReady = false
    @Published var hasCameraFrame = false
    @Published var liveLiDARStatus = "Starting camera…"

    weak var sceneView: ARSCNView?
    private let ciContext = CIContext()
    private var focalPixels: Double?

    var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }

    var selectionSizeM: CGSize? {
        guard let photo, points.count == 4 else { return nil }
        let metersPerPixel: Double
        if usesManualScale {
            guard manualReferencePoints.count == 2,
                  let lengthCM = Double(manualReferenceLengthCM.replacingOccurrences(of: ",", with: ".")),
                  lengthCM.isFinite, lengthCM > 0 else { return nil }
            let dx = Double((manualReferencePoints[0].x - manualReferencePoints[1].x) * photo.size.width)
            let dy = Double((manualReferencePoints[0].y - manualReferencePoints[1].y) * photo.size.height)
            let pixels = hypot(dx, dy)
            guard pixels >= 8 else { return nil }
            metersPerPixel = lengthCM / 100 / pixels
        } else {
            guard let distanceM, let focalPixels, focalPixels > 0 else { return nil }
            metersPerPixel = distanceM / focalPixels
        }
        func side(_ a: Int, _ b: Int) -> Double {
            let dx = Double((points[a].x - points[b].x) * photo.size.width)
            let dy = Double((points[a].y - points[b].y) * photo.size.height)
            return hypot(dx, dy) * metersPerPixel
        }
        return CGSize(width: (side(0, 1) + side(3, 2)) / 2,
                      height: (side(0, 3) + side(1, 2)) / 2)
    }

    var selectionHasScale: Bool {
        guard let size = selectionSizeM, let angle = nadirDeviationDegrees else { return false }
        return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            && angle.isFinite
    }

    func refreshLiveLiDARStatus() {
        guard let frame = sceneView?.session.currentFrame else {
            hasCameraFrame = false
            isLiDARReady = false
            liveLiDARStatus = "Starting camera…"
            return
        }
        hasCameraFrame = true
        guard hasLiDAR else {
            isLiDARReady = false
            liveLiDARStatus = "Manual scale"
            return
        }
        guard case .normal = frame.camera.trackingState else {
            isLiDARReady = false
            liveLiDARStatus = "Manual scale"
            return
        }
        guard let depth = frame.smoothedSceneDepth,
              let measuredDistance = Self.groundDistance(depth.depthMap) else {
            isLiDARReady = false
            liveLiDARStatus = "Manual scale"
            return
        }
        isLiDARReady = true
        liveLiDARStatus = String(format: "LiDAR · %.2f m", measuredDistance)
    }

    func capture() {
        guard let frame = sceneView?.session.currentFrame else {
            status = "Camera is starting. Try again in a moment."
            return
        }
        let trackingNormal: Bool
        if case .normal = frame.camera.trackingState { trackingNormal = true }
        else { trackingNormal = false }
        let measuredDistance: Double? = hasLiDAR && trackingNormal
            ? frame.smoothedSceneDepth.flatMap { Self.groundDistance($0.depthMap) }
            : nil
        let needsManualScale = measuredDistance == nil
        let source = frame.capturedImage
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let camera = frame.camera
        let focal = Double((camera.intrinsics.columns.0.x + camera.intrinsics.columns.1.y) / 2)
        guard focal > 0,
              let cg = ciContext.createCGImage(CIImage(cvPixelBuffer: source),
                                                from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            status = "Could not capture the camera image."
            return
        }
        // Normalize orientation before editing point coordinates.
        let oriented = UIImage(cgImage: cg, scale: 1, orientation: .right)
        let uprightSize = CGSize(width: height, height: width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: uprightSize, format: format).image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: uprightSize))
        }
        let up = camera.transform.columns.2
        let deviation = acos(min(1, abs(Double(up.y)))) * 180 / .pi
        photo = upright
        points = [CGPoint(x: 0.18, y: 0.18), CGPoint(x: 0.82, y: 0.18),
                  CGPoint(x: 0.82, y: 0.82), CGPoint(x: 0.18, y: 0.82)]
        usesManualScale = needsManualScale
        manualReferencePoints = [CGPoint(x: 0.32, y: 0.5), CGPoint(x: 0.68, y: 0.5)]
        manualReferenceLengthCM = ""
        distanceM = measuredDistance
        focalPixels = focal
        nadirDeviationDegrees = deviation
        moistureVWC = nil
        modelWarnings = []
        status = needsManualScale
            ? "Mark a known length on the soil."
            : "Drag the corners around the plant and nearby soil."
    }

    func movePoint(_ index: Int, to point: CGPoint) {
        guard points.indices.contains(index) else { return }
        points[index] = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
        moistureVWC = nil
        modelWarnings = []
    }

    func moveReferencePoint(_ index: Int, to point: CGPoint) {
        guard manualReferencePoints.indices.contains(index) else { return }
        manualReferencePoints[index] = CGPoint(x: min(1, max(0, point.x)),
                                               y: min(1, max(0, point.y)))
        moistureVWC = nil
        modelWarnings = []
    }

    func retake() {
        photo = nil
        points = []
        distanceM = nil
        usesManualScale = false
        manualReferencePoints = []
        manualReferenceLengthCM = ""
        focalPixels = nil
        nadirDeviationDegrees = nil
        moistureVWC = nil
        modelWarnings = []
        isLiDARReady = false
        hasCameraFrame = false
        liveLiDARStatus = "Starting camera…"
        status = "Frame the plant and nearby soil."
    }

    func predict() async {
        guard let photo, let size = selectionSizeM, let angle = nadirDeviationDegrees else {
            status = "Capture a photo and select four corners first."
            return
        }
        guard selectionHasScale else {
            status = "Set the image scale with LiDAR or a known-length reference first."
            return
        }
        let submittedPoints = points
        let submittedManual = usesManualScale
        isPredicting = true
        status = "Estimating on this iPhone…"
        defer { isPredicting = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try LocalVineyardModel.predict(photo: photo, points: submittedPoints,
                                               physicalSizeM: size,
                                               nadirDeviationDegrees: angle)
            }.value
            guard points == submittedPoints,
                  selectionSizeM == size, usesManualScale == submittedManual else {
                status = "Selection changed while estimating. Run the model again."
                return
            }
            moistureVWC = result.moisture
            modelWarnings = result.warnings + (submittedManual
                ? ["Manual scale assumes the reference lies on the same ground plane as the selected soil."] : [])
            status = "Estimate ready. Check with a soil probe."
        } catch {
            status = error.localizedDescription
        }
    }

    private static func groundDistance(_ buffer: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let pointer = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowWidth = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.stride
        let values = pointer.assumingMemoryBound(to: Float32.self)
        var sample: [Double] = []
        // Soil is usually farther than leaves. Sample the central 60% to include
        // ground around the vine, then take a high percentile rather than the
        // nearest return or one noisy maximum-depth pixel.
        for y in stride(from: height / 5, through: height * 4 / 5, by: max(1, height / 80)) {
            for x in stride(from: width / 5, through: width * 4 / 5, by: max(1, width / 80)) {
                let value = Double(values[y * rowWidth + x])
                if value.isFinite && (0.15...5.0).contains(value) { sample.append(value) }
            }
        }
        guard sample.count >= 30 else { return nil }
        sample.sort()
        return sample[Int(Double(sample.count - 1) * 0.85)]
    }
}
