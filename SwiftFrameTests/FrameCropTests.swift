import CoreGraphics
import Foundation
import Testing
@testable import SwiftFrame

@Suite struct FrameCropTests {
    let a6600 = FrameCrop(width: 1620, height: 1080)

    @Test func cropsHDMIToThePixel() {
        // 150 pixels off each side of 1920 × 1080, nothing off the top.
        #expect(a6600.rect(sourceWidth: 1920, sourceHeight: 1080) == CGRect(x: 150, y: 0, width: 1620, height: 1080))
        #expect(a6600.name == "a6600 1620×1080 (3:2)")
    }

    @Test func keepsTheShapeAtOtherSizes() {
        #expect(a6600.rect(sourceWidth: 3840, sourceHeight: 2160) == CGRect(x: 300, y: 0, width: 3240, height: 2160))
        // Wider than the picture: crops the top and bottom instead.
        let scope = FrameCrop(width: 1920, height: 804)
        #expect(scope.rect(sourceWidth: 1920, sourceHeight: 1080) == CGRect(x: 0, y: 138, width: 1920, height: 804))
        #expect(scope.ciRect(sourceWidth: 1920, sourceHeight: 1080) == CGRect(x: 0, y: 138, width: 1920, height: 804))
        let unit = a6600.unitRect(sourceWidth: 1920, sourceHeight: 1080)
        #expect(abs(unit.minX - 150.0 / 1920) < 1e-9 && unit.height == 1)
    }

    @Test func oldProjectsHaveNoCrop() throws {
        let json = #"{"version":1,"frames":[],"framesPerSecond":12,"onionSkinFrames":1,"onionSkinOpacity":0.4,"mirrorCamera":false,"loopPlayback":true}"#
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.crop == nil)
        var cropped = project
        cropped.crop = a6600
        let again = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(cropped))
        #expect(again.crop == a6600)
    }
}
