import Foundation
import Testing
@testable import AgentSafariCore

@Test func jsonValueEncodesStructuredObject() throws {
    let response = RPCResponse(
        id: "1",
        ok: true,
        result: .object([
            "count": .number(2),
            "capturing": .bool(true),
            "events": .array([.object(["url": .string("https://example.com")])])
        ]),
        error: nil
    )

    let data = try JSONEncoder().encode(response)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let result = try #require(object["result"] as? [String: Any])

    #expect(result["count"] as? Double == 2)
    #expect(result["capturing"] as? Bool == true)
    #expect((result["events"] as? [[String: Any]])?.first?["url"] as? String == "https://example.com")
}

@Test func jsonValueParsesJSONTextOrFallsBackToString() throws {
    #expect(JSONValue.parseJSONText("[{\"ref\":\"@e1\"}]") == .array([.object(["ref": .string("@e1")])]))
    #expect(JSONValue.parseJSONText("plain") == .string("plain"))
}

@Test func jsonValuePreservesIntegerZeroAndOneAsNumbersNotBooleans() throws {
    // JSONSerialization decodes JSON integers 0/1 as NSNumber that also casts to Bool;
    // fromJSONObject must keep them numeric and only treat real JSON booleans as bools.
    let parsed = JSONValue.parseJSONText("{\"readyState\":0,\"index\":1,\"paused\":true,\"ended\":false}")
    #expect(parsed == .object([
        "readyState": .number(0),
        "index": .number(1),
        "paused": .bool(true),
        "ended": .bool(false)
    ]))
}
