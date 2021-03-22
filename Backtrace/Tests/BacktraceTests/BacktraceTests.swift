import XCTest
@testable import Backtrace

final class BacktraceTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Backtrace().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
