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
    let netDiskInfo: DiskItem?
    let extraInfo: ChannelInfo?
}
struct ChannelInfo: Decodable {
    let channelName: String?
    let externalLinks: String?
    let videoFileCount: Int?
}
struct DiskItem: Decodable, Identifiable {
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
    var stableID: String { id?.value ?? landingPage ?? m3u8Url ?? fileUrl ?? name ?? "" }
    func clip(channel: String) -> Clip? {
        guard isFolder != true, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let source = WebAddress.media(m3u8Url) ?? WebAddress.media(fileUrl) ?? WebAddress.media(originUrl) else { return nil }
        return Clip(id: stableID.isEmpty ? source.absoluteString : stableID, title: name,
                    playbackURL: source, coverURL: WebAddress.media(coverImage),
                    shortLink: landingPage, channel: channel, duration: length)
    }
}
struct ChannelPage: Decodable { let list: [DiskItem]; let total: Int }
struct FeedResponse: Decodable {
    let feedId: String?
    let nextCursor: String?
    let hasMore: Bool
    let list: [FeedItem]
}
struct FeedItem: Decodable {
    let videoId: ServiceID
    let shortLink: String?
    let m3u8Url: String
    let videoName: String?
    let coverUrl: String?
    var clip: Clip? {
        guard !videoId.value.isEmpty, let url = WebAddress.media(m3u8Url) else { return nil }
        return Clip(id: videoId.value, title: videoName?.nilIfBlank ?? "Untitled clip", playbackURL: url,
                    coverURL: WebAddress.media(coverUrl), shortLink: shortLink, channel: "Discover", duration: nil)
    }
}
struct Clip: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let playbackURL: URL
    let coverURL: URL?
    let shortLink: String?
    let channel: String
    let duration: Double?
}
struct LinkVisit: Codable, Identifiable {
    let id: UUID
    let link: String
    let title: String
    let date: Date
}
struct LocalMovie: Codable, Identifiable, Hashable {
    let id: UUID
    let filename: String
    var title: String
    let date: Date
    let isExport: Bool
}
struct LibrarySnapshot: Codable {
    var favorites: [Clip] = []
    var history: [LinkVisit] = []
    var movies: [LocalMovie] = []
}
struct ChannelRoute: Identifiable, Hashable {
    let link: String
    let title: String
    var id: String { link }
}
struct PlayerRoute: Identifiable {
    let id = UUID()
    let clips: [Clip]
    let startID: String
}
enum WebAddress {
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
    let favoriteBaseLimit: Int?
    let firstAdRewardWatchCount: Int?
    let secondAdRewardWatchCount: Int?
    let thirdAdRewardWatchCount: Int?
}
struct AdConfiguration: Decodable {
    let adType: Int
    let advertiser: String?
    let config: AdUnitConfiguration
}
struct AdUnitConfiguration: Decodable { let appId: String?; let adUnitId: String? }
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
    struct Product: Decodable { let id: String; let usdPrice: String; let label: String }
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
