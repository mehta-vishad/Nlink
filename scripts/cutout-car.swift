// Lifts the car out of a photo onto a transparent background using Apple's
// Vision subject lifting (the same model as iOS "Lift Subject from Background").
//
//     swift scripts/cutout-car.swift <photo.jpg> <out.png>
//
// Vision may find several foreground instances (people, signs). The instance
// with the largest mask area is taken to be the car; the output is cropped to it.
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: cutout-car.swift <photo> <out.png>\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

let handler = VNImageRequestHandler(url: input)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let observation = request.results?.first else {
    FileHandle.standardError.write(Data("no foreground found\n".utf8))
    exit(1)
}

// Score each instance by how many mask pixels it owns.
let allInstances = observation.allInstances
var areas: [Int: Int] = [:]
for index in allInstances {
    let mask = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: index), from: handler)
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
    let stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float32>.size
    let base = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: Float32.self)
    var count = 0
    for y in Swift.stride(from: 0, to: height, by: 4) {
        for x in Swift.stride(from: 0, to: width, by: 4) where base[y * stride + x] > 0.5 { count += 1 }
    }
    CVPixelBufferUnlockBaseAddress(mask, .readOnly)
    areas[index] = count
}
let car = areas.max { $0.value < $1.value }!.key
print("instances: \(areas.sorted { $0.key < $1.key }.map { "#\($0.key)=\($0.value)" }.joined(separator: " ")) -> keeping #\(car)")

let masked = try observation.generateMaskedImage(
    ofInstances: IndexSet(integer: car), from: handler, croppedToInstancesExtent: true
)
let image = CIImage(cvPixelBuffer: masked)
let context = CIContext()
try context.writePNGRepresentation(
    of: image, to: output, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
)
print("wrote \(output.lastPathComponent): \(Int(image.extent.width))x\(Int(image.extent.height))")
