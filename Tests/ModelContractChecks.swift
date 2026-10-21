import Foundation

// Standalone contract regression checks; compile alongside Clipo/Core/LessonContracts.swift.
// Fixtures contain no account, token or real media URL.
@main
enum ModelContractChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        let landingLinks = [
            "http://192.168.101.96:3050/2DhdI8",
            "https://example.com/lessons/2DhdI8/?campaign=test#preview",
            "  2DhdI8  ",
            "https://example.com/%32DhdI8"
        ]
        precondition(landingLinks.compactMap { WebAddress.landingCode($0) } == Array(repeating: "2DhdI8", count: 4))
        for invalid in ["", "   ", "https://example.com/", "file:///private/code"] {
            precondition(WebAddress.landingCode(invalid) == nil)
        }
        func disk(_ json: String) throws -> RemoteLessonFile {
            try decoder.decode(RemoteLessonFile.self, from: Data(json.utf8))
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
        let ad = try decoder.decode(AdConfiguration.self, from: Data(#"{"adType":1,"advertiser":"google","config":{"appId":"demo","adUnitId":"demo"},"displayInterval":5,"adOrder":"15","showIntervalRows":null,"maxHourlyImps":"0"}"#.utf8))
        precondition(ad.displayInterval == 5)
        let stringInterval = try decoder.decode(AdConfiguration.self, from: Data(#"{"adType":1,"config":{},"displayInterval":"2.5"}"#.utf8))
        precondition(stringInterval.displayInterval == 2.5)
        let missingInterval = try decoder.decode(AdConfiguration.self, from: Data(#"{"adType":1,"config":{}}"#.utf8))
        let now = Date(timeIntervalSince1970: 1000)
        precondition(!AppOpenTiming.isDue(intervalMinutes: missingInterval.displayInterval, lastShown: nil, now: now))
        precondition(AppOpenTiming.isDue(intervalMinutes: 5, lastShown: nil, now: now))
        precondition(!AppOpenTiming.isDue(intervalMinutes: 5, lastShown: now.addingTimeInterval(-299), now: now))
        precondition(AppOpenTiming.isDue(intervalMinutes: 5, lastShown: now.addingTimeInterval(-300), now: now))
        precondition(AppOpenTiming.isDue(intervalMinutes: 0, lastShown: now, now: now))
        precondition(!AppOpenTiming.isDue(intervalMinutes: -1, lastShown: nil, now: now))
        precondition(!AppOpenTiming.isDue(intervalMinutes: .infinity, lastShown: nil, now: now))
        precondition(!AppOpenTiming.isDue(intervalMinutes: 1, lastShown: now.addingTimeInterval(60), now: now))
        print("PASS: media fields, folders, URL schemes, entitlement timestamps, app-open interval decoding and minute boundaries")
    }
}
