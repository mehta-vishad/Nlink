// Studio-style grade for a car cut-out: pulls down specular highlights and
// sky reflections, lifts shadows a touch and adds a little saturation, so a
// daylight photo reads closer to a manufacturer's studio render. Alpha is
// preserved.
//
//     swift scripts/neutralize-car.swift <cutout.png> <out.png>
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

let args = CommandLine.arguments
let input = CIImage(contentsOf: URL(fileURLWithPath: args[1]))!

let tone = CIFilter.highlightShadowAdjust()
tone.inputImage = input
tone.highlightAmount = 0.78   // < 1 compresses highlights / reflections
tone.shadowAmount = 0.22      // > 0 opens up shadows
tone.radius = 12

let color = CIFilter.colorControls()
color.inputImage = tone.outputImage
color.saturation = 1.08
color.contrast = 1.03
color.brightness = -0.01

let out = color.outputImage!.cropped(to: input.extent)
try! CIContext().writePNGRepresentation(
    of: out, to: URL(fileURLWithPath: args[2]), format: .RGBA8,
    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
)
print("wrote \(args[2])")
