import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let msg: String?
    let data: Value?
}

// The service returns some identifiers as either JSON numbers or strings.
struct ServiceID: Codable, Hashable {
    let value: String
    init(_ value: String) { self.value = value }
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let string = try? box.decode(String.self) { value = string }
        else { value = String(try box.decode(Int64.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        try box.encode(value)
    }
}

struct VisitorSession: Codable {
    let accessToken: String
    let userId: ServiceID
    let domainId: ServiceID?
    let shortLink: String?
}

struct ReleaseConfiguration: Decodable {
    var recommend: [RecommendedSite]?
    var lcList: [String: [String]]?
    var NB01: Bool?
    var ios: IOSBillingConfiguration?
    var quotaConfig: QuotaConfiguration?
    var adList: [AdConfiguration]?
}
struct RecommendedSite: Decodable, Identifiable {
    let name: String
    let url: String
    let pictureUrl: String?
    var id: String { url }
}
struct LandingInfo: Decodable {
    let shortCover: String?
    let netDiskInfo: RemoteLessonFile?
    let extraInfo: ChannelInfo?
}
struct ChannelInfo: Decodable {
    let channelName: String?
    let externalLinks: String?
    let videoFileCount: Int?
}
struct RemoteLessonFile: Decodable, Identifiable {
    let id: ServiceID?
    let landingPage: String?
    let name: String?
    let coverImage: String?
    let m3u8Url: String?
    let fileUrl: String?
    let originUrl: String?
    let length: Double?
    let fileSize: Double?
    let isFolder: Bool?
    let childrenFileNum: Int?
    private enum CodingKeys: String, CodingKey {
        case id, landingPage, name, coverImage, m3u8Url, fileUrl, originUrl
        case length, fileSize, isFolder, childrenFileNum, extraInfo
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(ServiceID.self, forKey: .id)
        landingPage = try values.decodeIfPresent(String.self, forKey: .landingPage)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        coverImage = try values.decodeIfPresent(String.self, forKey: .coverImage)
        m3u8Url = try values.decodeIfPresent(String.self, forKey: .m3u8Url)
        fileUrl = try values.decodeIfPresent(String.self, forKey: .fileUrl)
        originUrl = try values.decodeIfPresent(String.self, forKey: .originUrl)
        length = try values.decodeMediaNumber(forKey: .length)
        fileSize = try values.decodeMediaNumber(forKey: .fileSize)
        isFolder = try values.decodeIfPresent(Bool.self, forKey: .isFolder)
        // The contract allows folder counts at either level. Prefer the direct value.
        struct ExtraInfo: Decodable { let childrenFileNum: Int? }
        childrenFileNum = try values.decodeIfPresent(Int.self, forKey: .childrenFileNum)
            ?? values.decodeIfPresent(ExtraInfo.self, forKey: .extraInfo)?.childrenFileNum
    }
    var stableID: String { id?.value ?? landingPage ?? m3u8Url ?? fileUrl ?? name ?? "" }
    func clip(channel: String) -> LessonClip? {
        guard isFolder != true, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let source = WebAddress.media(m3u8Url) ?? WebAddress.media(fileUrl) ?? WebAddress.media(originUrl) else { return nil }
        return LessonClip(id: stableID.isEmpty ? source.absoluteString : stableID, title: name,
                    playbackURL: source, coverURL: WebAddress.media(coverImage),
                    shortLink: landingPage, channel: channel, duration: length,
                    exportSources: [fileUrl, originUrl].compactMap { WebAddress.media($0) })
    }
}
private extension KeyedDecodingContainer {
    // The live media API uses both JSON numbers and numeric strings (e.g. length: "50").
    func decodeMediaNumber(forKey key: Key) throws -> Double? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(Double.self, forKey: key), value.isFinite { return value }
        let text = try decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text), value.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a finite media number.")
        }
        return value
    }
}
struct ChannelPage: Decodable { let list: [RemoteLessonFile]; let total: Int }
struct LessonFeedPage: Decodable {
    let feedId: String?
    let nextCursor: String?
    let hasMore: Bool
    let list: [RecommendedLesson]
}
struct RecommendedLesson: Decodable {
    let videoId: ServiceID
    let shortLink: String?
    let m3u8Url: String
    let videoName: String?
    let coverUrl: String?
    // Optional original-file fields, when supplied. HLS remains the playback source.
    let fileUrl: String?
    let originUrl: String?
    var clip: LessonClip? {
        guard !videoId.value.isEmpty, let url = WebAddress.media(m3u8Url) else { return nil }
        return LessonClip(id: videoId.value, title: videoName?.nilIfBlank ?? "Untitled clip", playbackURL: url,
                    coverURL: WebAddress.media(coverUrl), shortLink: shortLink, channel: "Discover", duration: nil,
                    exportSources: [fileUrl, originUrl].compactMap { WebAddress.media($0) })
    }
}
struct LessonClip: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let playbackURL: URL
    let coverURL: URL?
    let shortLink: String?
    let channel: String
    let duration: Double?
    // Optional for compatibility with existing favorites and offline indexes.
    var exportSources: [URL]? = nil
}
struct LessonLinkVisit: Codable, Identifiable {
    let id: UUID
    let link: String
    let title: String
    let date: Date
}
struct PracticeRecording: Codable, Identifiable, Hashable {
    let id: UUID
    let filename: String
    var title: String
    let date: Date
    let isExport: Bool
}
struct LessonLibrarySnapshot: Codable {
    var favorites: [LessonClip] = []
    var history: [LessonLinkVisit] = []
    var movies: [PracticeRecording] = []
}
struct ChannelRoute: Identifiable, Hashable {
    let link: String
    let title: String
    var id: String { link }
}
// Separate scroll occurrence from video identity: a new recommendation round may
// repeat a lesson without sharing AVPlayer state or charging it again.
struct PlaybackQueueEntry: Identifiable, Equatable {
    let id: String
    let clip: LessonClip
}
struct PlayerRoute: Identifiable {
    let id = UUID()
    let clips: [LessonClip]
    let startID: String
    var continuesRecommendations = false
}
enum WebAddress {
    // Collection lookup accepts a code, whereas search-check accepts raw input.
    // Parse URLs structurally so query strings, fragments and trailing slashes
    // cannot leak into the collection's externalLinks field.
    static func landingCode(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = media(value) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let component = components.percentEncodedPath.split(separator: "/").last else { return nil }
            return String(component).removingPercentEncoding?.nilIfBlank
        }
        guard !value.contains(":"), !value.contains("/"),
              !value.contains("?"), !value.contains("#") else { return nil }
        return value
    }
    static func media(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}
extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

struct IOSBillingConfiguration: Codable { let iosVerifyShareKey: String?; let sandBoxTest: Bool? }
struct QuotaConfiguration: Decodable {
    let dailyWatchLimit: Int?
    // Backend field names are misleading; the confirmed API comments define their roles.
    let dailyDownloadLimit: Int?
    let downloadRewardCount: Int?
    let firstAdRewardWatchCount: Int?
    let secondAdRewardWatchCount: Int?
    let thirdAdRewardWatchCount: Int?
    private enum CodingKeys: String, CodingKey {
        case dailyWatchLimit, firstAdRewardWatchCount, secondAdRewardWatchCount, thirdAdRewardWatchCount
        case dailyDownloadLimit = "unlimitedAfterAdCount"
        case downloadRewardCount = "favoriteBaseLimit"
    }
}
struct AdConfiguration: Decodable {
    let adType: Int
    let advertiser: String?
    let config: AdUnitConfiguration
    let displayInterval: Double?

    private enum CodingKeys: String, CodingKey { case adType, advertiser, config, displayInterval }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        adType = try values.decode(Int.self, forKey: .adType)
        advertiser = try values.decodeIfPresent(String.self, forKey: .advertiser)
        config = try values.decode(AdUnitConfiguration.self, forKey: .config)
        displayInterval = try values.decodeMediaNumber(forKey: .displayInterval)
    }
}

enum AppOpenTiming {
    // Server interval is in minutes. Missing/negative configuration is not permission to show.
    static func isDue(intervalMinutes: Double?, lastShown: Date?, now: Date = Date()) -> Bool {
        guard let minutes = intervalMinutes, minutes.isFinite, minutes >= 0,
              (minutes * 60).isFinite else { return false }
        guard let lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= minutes * 60
    }
}
struct AdUnitConfiguration: Decodable { let appId: String?; let adUnitId: String? }

struct GoogleAdPlacement {
    let appID: String
    let unitID: String
    let isOfficialDemo: Bool
}
extension ReleaseConfiguration {
    // App ID comes from getV2 and must agree with the SDK's packaged identity.
    // Never substitute a sample ad unit for a missing or invalid server value.
    func googlePlacement(for type: Int, packagedAppID: String?) -> GoogleAdPlacement? {
        let matches = (adList ?? []).filter {
            $0.adType == type && $0.advertiser?.lowercased() == "google"
        }
        guard matches.count == 1, let unit = matches.first,
              let appID = unit.config.appId?.nilIfBlank,
              let unitID = unit.config.adUnitId?.nilIfBlank,
              appID == packagedAppID,
              appID.range(of: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#, options: .regularExpression) != nil,
              unitID.range(of: #"^ca-app-pub-[0-9]{16}/[0-9]{10}$"#, options: .regularExpression) != nil,
              appID.split(separator: "~").first == unitID.split(separator: "/").first else { return nil }
        let demoApp = appID == "ca-app-pub-3940256099942544~1458002511"
        let demoUnit = (type == 1 && unitID == "ca-app-pub-3940256099942544/5575463023")
            || (type == 5 && unitID == "ca-app-pub-3940256099942544/1712485313")
        if demoApp && !demoUnit { return nil }
        return GoogleAdPlacement(appID: appID, unitID: unitID, isOfficialDemo: demoApp && demoUnit)
    }
}

struct UserRights: Decodable {
    let rightExpireTime: ServiceID?
    var expiration: Date? {
        guard let raw = rightExpireTime?.value else { return nil }
        if let number = Double(raw), number.isFinite {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        let formatter = ISO8601DateFormatter()
        if let value = formatter.date(from: raw) { return value }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from: raw) { return date }
        let localFormat = DateFormatter()
        localFormat.locale = Locale(identifier: "en_US_POSIX")
        localFormat.timeZone = .current
        localFormat.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return localFormat.date(from: raw)
    }
}
struct CommerceConfiguration: Decodable {
    struct Product: Decodable, Identifiable {
        enum BillingPeriod: String, Decodable { case month, year }
        let id: String
        let usdPrice: String // Fixed USD plan value (999 / 9999); send unchanged, no currency conversion.
        let label: String
        // Reference display values are separate from the backend's usdPrice contract.
        let displayPriceUSD: String
        let period: BillingPeriod
    }
    let products: [Product]
    let rewardedAdType: Int
    let unlimitedAfterCompletedAds: Int
    let favoriteReward: Int
    let dailyWatchLimit: Int
    let dailyFavoriteLimit: Int
    let watchRewards: [Int]
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "Commerce", withExtension: "json") else { throw ClipoError.configuration }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

enum ClipoError: LocalizedError {
    case configuration, invalidResponse, unauthorized, service(String), storage, unsupportedMedia
    var errorDescription: String? {
        switch self {
        case .configuration: return "Clipo’s online service is not configured yet. Local editing is available."
        case .invalidResponse: return "The service returned an unreadable response. Please try again."
        case .unauthorized: return "Your session has expired. Please sign in again."
        case .service(let message): return message
        case .storage: return "Your changes could not be saved on this device. Please try again."
        case .unsupportedMedia: return "This video cannot be edited. Import a local video file to continue."
        }
    }
    static func connectionFailure(_ error: Error) -> Error {
        guard let error = error as? URLError else { return error }
        switch error.code {
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return ClipoError.service("A secure connection to Clipo could not be established. Check your network or VPN, then try again. If it continues, the service may be temporarily unavailable.")
        case .notConnectedToInternet, .networkConnectionLost:
            return ClipoError.service("Your internet connection was interrupted. Reconnect and try again.")
        case .timedOut:
            return ClipoError.service("The service took too long to respond. Please try again.")
        default: return error
        }
    }
}
