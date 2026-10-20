import Foundation

// Standalone contract regression checks; compile alongside Clipo/Core/Models.swift.
// Fixtures contain no account, token or real media URL.
@main
enum ModelContractChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        func disk(_ json: String) throws -> DiskItem {
            try decoder.decode(DiskItem.self, from: Data(json.utf8))
        }
        let numeric = try disk(#"{"id":123,"name":"Clip","length":50,"fileSize":1024,"isFolder":false}"#)
        precondition(numeric.id?.value == "123" && numeric.length == 50 && numeric.fileSize == 1024)
        let strings = try disk(#"{"id":"123","name":"Clip","length":"50","fileSize":" 1024 "}"#)
        precondition(strings.length == numeric.length && strings.fileSize == numeric.fileSize)
        let missing = try disk(#"{"length":null,"fileSize":null}"#)
        precondition(missing.length == nil && missing.fileSize == nil)
        for invalid in [#"{"length":"not-a-number"}"#, #"{"length":"NaN"}"#, #"{"fileSize":true}"#] {
            do { _ = try disk(invalid); fatalError("Invalid media number was accepted") }
            catch is DecodingError { }
        }
        let folder = try disk(#"{"id":"folder","name":"Folder","isFolder":true,"m3u8Url":"https://example.com/a.m3u8"}"#)
        precondition(folder.clip(channel: "Test") == nil)
        let nestedFolder = try disk(#"{"isFolder":true,"extraInfo":{"childrenFileNum":6}}"#)
        let directFolder = try disk(#"{"childrenFileNum":2,"extraInfo":{"childrenFileNum":6}}"#)
        precondition(nestedFolder.childrenFileNum == 6 && directFolder.childrenFileNum == 2)
        let clip = try disk(#"{"id":"clip","name":"Clip","isFolder":false,"m3u8Url":"https://example.com/a.m3u8"}"#)
        precondition(clip.clip(channel: "Test")?.id == "clip")
        for raw in ["file:///private/token", "javascript:alert(1)", "relative/path", ""] {
            precondition(WebAddress.media(raw) == nil)
        }
        let seconds = try decoder.decode(UserRights.self, from: Data(#"{"rightExpireTime":1710000000}"#.utf8))
        let millis = try decoder.decode(UserRights.self, from: Data(#"{"rightExpireTime":"1710000000000"}"#.utf8))
        let iso = try decoder.decode(UserRights.self, from: Data(#"{"rightExpireTime":"2024-03-09T16:00:00Z"}"#.utf8))
        precondition(seconds.expiration == millis.expiration && seconds.expiration == iso.expiration)
        print("PASS: numeric/string media fields, nulls, invalid values, folder filtering, URL schemes, entitlement timestamps")
    }
}
