// Turns a transparent car cut-out (from scripts/cutout-car.swift) into the
// widget's image set: @2x and @3x PNGs plus Contents.json.
//
//     swift scripts/make-car-asset.swift <cutout.png> <Name.imageset> <points-wide> [--fade-left]
//
// --fade-left ramps the leftmost 7% to transparent, for photos whose rear is
// cropped by the frame; the widget lets that side bleed off its left edge.
// Widget extensions have a small memory ceiling, so the image is sized to the
// slot it fills rather than shipped at camera resolution.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

let args = CommandLine.arguments
guard args.count >= 4, let points = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: make-car-asset.swift <cutout.png> <Name.imageset> <points-wide> [--fade-left]\n".utf8))
    exit(2)
}
let source = CIImage(contentsOf: URL(fileURLWithPath: args[1]))!
let imageset = URL(fileURLWithPath: args[2])
let fadeLeft = args.contains("--fade-left")
let name = imageset.deletingPathExtension().lastPathComponent
try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)

var image = source
if fadeLeft {
    let width = source.extent.width
    let ramp = CIFilter.smoothLinearGradient()
    ramp.point0 = CGPoint(x: source.extent.minX, y: 0)
    ramp.point1 = CGPoint(x: source.extent.minX + width * 0.07, y: 0)
    ramp.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
    ramp.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
    let mask = ramp.outputImage!.cropped(to: source.extent)
    let blend = CIFilter.blendWithAlphaMask()
    blend.inputImage = source
    blend.backgroundImage = CIImage.empty()
    blend.maskImage = mask
    image = blend.outputImage!.cropped(to: source.extent)
}

let context = CIContext()
var files: [(scale: Int, file: String)] = []
for scale in [2, 3] {
    let targetWidth = points * Double(scale)
    let factor = targetWidth / image.extent.width
    let resize = CIFilter.lanczosScaleTransform()
    resize.inputImage = image
    resize.scale = Float(factor)
    resize.aspectRatio = 1
    let out = resize.outputImage!
    let file = "\(name)@\(scale)x.png"
    try context.writePNGRepresentation(
        of: out, to: imageset.appending(path: file), format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
    )
    files.append((scale, file))
    print("\(file): \(Int(out.extent.width))x\(Int(out.extent.height))")
}

let images = [["idiom": "universal", "scale": "1x"]] + files.map {
    ["filename": $0.file, "idiom": "universal", "scale": "\($0.scale)x"]
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: imageset.appending(path: "Contents.json"))
