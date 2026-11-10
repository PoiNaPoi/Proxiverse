import AppKit
import XCTest
@testable import Reqnivo

final class MessagePreviewTests: XCTestCase {
    private func message(body: String, truncated: Bool = false, streamed: Bool = false) -> FlowMessage {
        FlowMessage(headers: [["content-type", "application/json"], ["set-cookie", "a=1"], ["set-cookie", "b=2"]],
                    body: body, truncated: truncated, streamed: streamed, httpVersion: "HTTP/2.0")
    }

    func testFormatsNestedJSONAndEmptyContainers() {
        XCTAssertEqual(MessagePreview.prettyJSON(#"{"cards":[{"active":true,"balance":null}],"empty":{},"list":[]}"#), """
        {
          "cards": [
            {
              "active": true,
              "balance": null
            }
          ],
          "empty": {},
          "list": []
        }
        """)
    }

    func testFormattingPreservesNumberLexemesKeyOrderAndEscapes() {
        let input = #"{"z":123456789012345678901234567890,"amount":-0.0012300e+04,"a":"quote: \" and slash: \\ and unicode: \u0e01"}"#
        let formatted = MessagePreview.prettyJSON(input)
        XCTAssertNotNil(formatted)
        XCTAssertTrue(formatted!.contains("123456789012345678901234567890"))
        XCTAssertTrue(formatted!.contains("-0.0012300e+04"))
        XCTAssertTrue(formatted!.contains(#""a": "quote: \" and slash: \\ and unicode: \u0e01""#))
        XCTAssertTrue(formatted!.hasPrefix("{\n  \"z\""))
    }

    func testHandlesFragmentsAndLeavesNonJSONUnchanged() {
        XCTAssertEqual(MessagePreview.prettyJSON("true"), "true")
        XCTAssertEqual(MessagePreview.prettyJSON("null"), "null")
        XCTAssertEqual(MessagePreview.prettyJSON(#""สวัสดี 👋""#), #""สวัสดี 👋""#)
        for text in ["", "<html>error</html>", #"{"incomplete":true"#, #"{"invalid":01}"#] {
            let rendered = MessagePreview.render(message(body: text))
            XCTAssertFalse(rendered.isJSON)
            XCTAssertEqual(rendered.body.string, text)
            XCTAssertEqual(rendered.copyText, text)
        }
    }

    func testCopyUsesExactlyTheFormattedJSONDisplayed() {
        let rendered = MessagePreview.render(message(body: #"{"ok":true,"count":3}"#))
        XCTAssertTrue(rendered.isJSON)
        XCTAssertEqual(rendered.copyText, rendered.body.string)
        XCTAssertTrue(rendered.copyText.contains("\n"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(rendered.copyText.utf8)))
    }

    func testIncompleteAndStreamedBodiesAreNeverPresentedAsCompleteJSON() {
        for value in [message(body: #"{"ok":true}"#, truncated: true), message(body: "", streamed: true)] {
            XCTAssertFalse(MessagePreview.render(value).isJSON)
        }
    }

    func testHighlightsKeysStringsNumbersAndLiteralsIndependently() {
        let text = #"{"key":"value","count":12,"active":true,"missing":null}"#
        let rendered = MessagePreview.highlightedJSON(text)
        let source = text as NSString
        func color(_ token: String) -> NSColor? {
            rendered.attribute(.foregroundColor, at: source.range(of: token).location, effectiveRange: nil) as? NSColor
        }
        XCTAssertEqual(color("\"key\""), .systemPurple)
        XCTAssertEqual(color("\"value\""), .systemGreen)
        XCTAssertEqual(color("12"), .systemOrange)
        XCTAssertEqual(color("true"), .systemBlue)
        XCTAssertEqual(color("null"), .secondaryLabelColor)
    }

    func testHeadersRetainDuplicateFieldsAndUseSeparateNameValueColors() {
        let rendered = MessagePreview.highlightedHeaders(message(body: ""))
        XCTAssertEqual(rendered.string, "HTTP/2.0\n\ncontent-type: application/json\nset-cookie: a=1\nset-cookie: b=2\n")
        let source = rendered.string as NSString
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: source.range(of: "content-type").location, effectiveRange: nil) as? NSColor, .systemBlue)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: source.range(of: "application/json").location, effectiveRange: nil) as? NSColor, .systemGreen)
    }

    func testMockEditorFormattingCanUseTheLargerBodyBudgetWithoutChangingInspectorLimits() {
        let value = String(repeating: "x", count: 2 * 1024 * 1024)
        let body = "{\"text\":\"" + value + "\"}"
        XCTAssertTrue(MessagePreview.prettyJSON(body) == nil, "Inspector retains its 2 MiB formatting budget")
        XCTAssertTrue(MessagePreview.prettyJSON(body, maximumBytes: RuleStore.maximumMockBytes) ==
                      "{\n  \"text\": \"" + value + "\"\n}", "Large string tokens must be preserved in full")
        let small = #"{"ok":true}"#
        let formatted = "{\n  \"ok\": true\n}"
        XCTAssertEqual(MessagePreview.prettyJSON(small, maximumBytes: formatted.utf8.count), formatted)
        XCTAssertNil(MessagePreview.prettyJSON(small, maximumBytes: formatted.utf8.count - 1))
    }
}
