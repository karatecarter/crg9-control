import XCTest
@testable import CRG9Core
final class Fake: CommandRunning {
    var replies: [String]; var calls: [[String]] = []
    init(_ replies: [String]) { self.replies = replies }
    func run(_ arguments: [String]) throws -> String {
        calls.append(arguments)
        guard !replies.isEmpty else { throw ControlError("Disconnected") }
        return replies.removeFirst()
    }
}
final class ControlTests: XCTestCase {
    static let listing = """
    [1] (EDID not readable: error)
    [2] C49RG9x (TEST-123)
     - Product name:  C49RG9x
     - Manufacturer:  SAM
     - AN Serial:     TEST-123
     - Display ID:    1
    [3] Other display (OTHER)
     - Product name:  Other display
     - Manufacturer:  AUS
     - AN Serial:     OTHER
     - Display ID:    2
    """
    func testSamsungCodes() {
        XCTAssertEqual(MonitorInput.dp1.value,9); XCTAssertEqual(MonitorInput.dp2.value,10); XCTAssertEqual(MonitorInput.hdmi.value,6)
        XCTAssertNil(MonitorInput(value:15))
    }
    func testDetection() {
        let found=MonitorControl.parseDisplays(Self.listing)
        XCTAssertEqual(found.count,1); XCTAssertEqual(found[0].selector,"serial=TEST-123"); XCTAssertTrue(found[0].online)
        let inactive=MonitorControl.parseDisplays(Self.listing.replacingOccurrences(of:"Display ID:    1",with:"Display ID:    none (not driven by macOS)"))
        XCTAssertFalse(inactive[0].online)
        XCTAssertTrue(MonitorControl.parseDisplays(Self.listing.replacingOccurrences(of:"AN Serial:     TEST-123",with:"AN Serial:     ")).isEmpty)
    }
    func testAmbiguousAndMissingTargets() throws {
        let a=Monitor(name:"C49RG9x",serial:"A",selector:"serial=A",online:true)
        let b=Monitor(name:"C49RG9x",serial:"B",selector:"serial=B",online:true)
        XCTAssertThrowsError(try MonitorControl.select([a,b],target:nil))
        XCTAssertThrowsError(try MonitorControl.select([a,b],target:"auto"))
        XCTAssertEqual(try MonitorControl.select([a],target:"auto"),a)
        XCTAssertThrowsError(try MonitorControl.select([a,b],target:"missing"))
        XCTAssertEqual(try MonitorControl.select([a,b],target:"B"),b)
        XCTAssertEqual(try MonitorControl.select([a,b],target:"serial=A"),a)
    }
    func testDuplicateSerialFailsClosed() {
        let fake=Fake([Self.listing+"\n"+Self.listing])
        XCTAssertThrowsError(try MonitorControl(runner:fake).displays())
    }
    func testUnknownAndInvalidReadback() throws {
        let fake=Fake([Self.listing,"99"])
        let status=try MonitorControl(runner:fake).status()
        XCTAssertEqual(status.input.name,"unknown"); XCTAssertEqual(status.input.value,99)
        XCTAssertEqual(fake.calls.last,["display","serial=TEST-123","get","input"])
        XCTAssertThrowsError(try MonitorControl(runner:Fake([Self.listing,"Writing 9"])).status())
    }
    func testVerifiedDP2() throws {
        let fake=Fake([Self.listing,"Writing 10","10"])
        let result=try MonitorControl(runner:fake).setInput(.dp2)
        XCTAssertEqual(result.verified,true); XCTAssertNil(result.warning)
        XCTAssertEqual(fake.calls[1],["display","serial=TEST-123","set","input","10"])
    }
    func testIgnoredWriteIsNotSuccess() throws {
        let result=try MonitorControl(runner:Fake([Self.listing,"Writing 10","9","9"])).setInput(.dp2)
        XCTAssertEqual(result.verified,false); XCTAssertTrue(result.warning!.contains("1007.3"))
    }
    func testDisconnectedAfterWrite() throws {
        let result=try MonitorControl(runner:Fake([Self.listing,"Writing 6"])).setInput(.hdmi)
        XCTAssertEqual(result.verified,false); XCTAssertNil(result.observedInput)
        XCTAssertTrue(result.warning!.contains("stopped answering"))
    }
    func testExplicitNoVerify() throws {
        let fake=Fake([Self.listing,"Writing 9"])
        let result=try MonitorControl(runner:fake).setInput(.dp1,verify:false)
        XCTAssertNil(result.verified); XCTAssertEqual(fake.calls.count,2)
    }
    func testFailedWriteThrows() {
        XCTAssertThrowsError(try MonitorControl(runner:Fake([Self.listing])).setInput(.hdmi))
    }
}
