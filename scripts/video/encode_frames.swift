import AVFoundation
import CoreGraphics
import ImageIO
import Foundation

// usage: encode <framesDir> <out.mp4> <bitrate>
let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2]), bitrate = Int(args[3]) ?? 2_000_000
struct Frame: Decodable { let f: String; let t: Double }
struct Manifest: Decodable { let duration: Double; let frames: [Frame] }
let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("manifest.json")))
let W = 1920, H = 1080, fps = 30
try? FileManager.default.removeItem(at: out)
let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                    AVVideoMaxKeyFrameIntervalKey: fps * 2, AVVideoExpectedSourceFrameRateKey: fps]])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)

func buffer(_ name: String) -> CVPixelBuffer {
  let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil)!
  let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
  var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
  CVPixelBufferLockBaseAddress(pb!, [])
  let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!),
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  ctx.interpolationQuality = .high
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
  CVPixelBufferUnlockBaseAddress(pb!, [])
  return pb!
}
let total = Int((m.duration * Double(fps)).rounded())
var j = 0, cur = "", pb: CVPixelBuffer? = nil
for i in 0..<total {
  let t = Double(i) / Double(fps)
  while j + 1 < m.frames.count && m.frames[j + 1].t <= t { j += 1 }
  if m.frames[j].f != cur { cur = m.frames[j].f; pb = buffer(cur) }
  while !input.isReadyForMoreMediaData { usleep(2000) }
  adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
print(writer.status == .completed ? "ok \(total) frames \(Double(total)/Double(fps))s" : "failed \(String(describing: writer.error))")
