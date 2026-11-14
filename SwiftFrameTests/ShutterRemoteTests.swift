import Foundation
import Testing
@testable import SwiftFrame

@Suite struct ShutterRemoteTests {
    @Test func recognizesSonyCameras() {
        // Sony (2D 01), a camera (03 00), then model details.
        #expect(SonyRemote.isSonyCamera(manufacturerData: Data([0x2D, 0x01, 0x03, 0x00, 0x64, 0x00, 0x45, 0x31])))
        // Another Sony product, another company, and too little data.
        #expect(!SonyRemote.isSonyCamera(manufacturerData: Data([0x2D, 0x01, 0x01, 0x00])))
        #expect(!SonyRemote.isSonyCamera(manufacturerData: Data([0x4C, 0x00, 0x03, 0x00])))
        #expect(!SonyRemote.isSonyCamera(manufacturerData: Data([0x2D, 0x01])))
        #expect(!SonyRemote.isSonyCamera(manufacturerData: nil))
    }

    @Test func clicksTheShutterLikeTheRemote() {
        // Half press, full press, full release, half release.
        #expect(SonyRemote.shutterClick == [[0x01, 0x07], [0x01, 0x09], [0x01, 0x08], [0x01, 0x06]])
    }
}
