import AppKit
import XCTest
@testable import Reqnivo

final class JSONFoldingTests: XCTestCase {
    private func presentation(_ body: String) -> MessagePresentation {
        MessagePreview.render(FlowMessage(headers: [], body: body, truncated: false, streamed: false, httpVersion: "HTTP/2.0"))
    }

    func testFindsNestedObjectsAndArraysButNotEmptyContainersOrQuotedBrackets() {
        let document = presentation(#"{"text":"{ [ \\\" } ] 😀","items":[{"id":1}],"empty":{},"list":[]}"#)
        XCTAssertTrue(document.isJSON)
        XCTAssertEqual(document.folds.count, 3)
        XCTAssertEqual(document.folds.first?.opening, 0)
        XCTAssertEqual(document.folds.last?.line, 3)
        XCTAssertTrue(document.folds.allSatisfy { $0.opening < $0.closing })
    }

    func testRootCanCollapseAndExpandWithoutChangingOriginalOrCopyText() throws {
        let document = presentation(#"{"name":"sample","items":[1,2,3]}"#)
        let root = try XCTUnwrap(document.folds.first)
        let folded = JSONFolding.display(document.body, regions: document.folds, collapsed: [root.opening])
        XCTAssertEqual(folded.content.string, "{ … }")
        XCTAssertEqual(folded.controls.count, 1)
        XCTAssertTrue(folded.controls[0].collapsed)
        XCTAssertTrue(document.copyText.contains("\"sample\""))
        XCTAssertTrue(document.copyText.contains("\n"))
        XCTAssertEqual(document.body.string, document.copyText)
        let expanded = JSONFolding.display(document.body, regions: document.folds, collapsed: [])
        XCTAssertTrue(expanded.content.isEqual(to: document.body))
        XCTAssertEqual(expanded.controls.count, document.folds.count)
    }

    func testNestedCollapseSurvivesCollapsingAndExpandingParent() throws {
        let document = presentation(#"{"items":[{"id":12345678901234567890}],"ok":true}"#)
        let root = try XCTUnwrap(document.folds.first)
        let array = document.folds[1]
        let childFolded = JSONFolding.display(document.body, regions: document.folds, collapsed: [array.opening])
        XCTAssertTrue(childFolded.content.string.contains("\"items\": [ … ]"))
        XCTAssertTrue(childFolded.content.string.contains("\"ok\": true"))
        XCTAssertEqual(childFolded.controls.count, 2)
        let allFolded = JSONFolding.display(document.body, regions: document.folds, collapsed: [root.opening, array.opening])
        XCTAssertEqual(allFolded.content.string, "{ … }")
        let restored = JSONFolding.display(document.body, regions: document.folds, collapsed: [array.opening])
        XCTAssertEqual(restored.content.string, childFolded.content.string)
        XCTAssertTrue(document.copyText.contains("12345678901234567890"))
    }

    func testMultipleSiblingFoldsHaveCorrectOffsetsAndPreserveColors() {
        let document = presentation(#"{"emoji":"😀","left":[1,2],"right":{"enabled":true},"tail":99}"#)
        let collapsed = Set(document.folds.dropFirst().map(\.opening))
        let folded = JSONFolding.display(document.body, regions: document.folds, collapsed: collapsed)
        XCTAssertTrue(folded.content.string.contains("\"left\": [ … ]"))
        XCTAssertTrue(folded.content.string.contains("\"right\": { … }"))
        let source = folded.content.string as NSString
        for control in folded.controls {
            XCTAssertTrue(["{", "["].contains(source.substring(with: NSRange(location: control.location, length: 1))))
        }
        let number = source.range(of: "99")
        XCTAssertEqual(folded.content.attribute(.foregroundColor, at: number.location, effectiveRange: nil) as? NSColor, .systemOrange)
    }

    func testPlainTextAndScalarJSONHaveNoFoldControls() {
        for body in ["not json", "42", "true", #""[quoted]""#, "{}", "[]"] {
            XCTAssertTrue(presentation(body).folds.isEmpty)
        }
    }

    func testIncompleteOrMismatchedContainersDoNotBecomeFolds() {
        for text in ["{\n]", "[\n}", "{\n  \"items\": [\n}"] {
            XCTAssertTrue(JSONFolding.regions(in: text).isEmpty)
        }
        XCTAssertEqual(JSONFolding.regions(in: "{\r\n  \"items\": [\r\n    1\r\n  ]\r\n}").map(\.line), [0, 1])
    }
}
