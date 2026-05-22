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
