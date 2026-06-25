import Foundation

nonisolated struct GalleryVideo: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let songTitle: String?
    let url: String?
    let thumbnailUrl: String?
    let createdBy: String?
    let createdDate: String?
    var thumbnailURL: URL? {
        thumbnailUrl.flatMap(URL.init(string:))
    }

    var embedURL: URL? {
        url.flatMap(URL.init(string:))
    }

    var streamURL: URL? {
        guard let thumb = thumbnailUrl, let comps = URLComponents(string: thumb),
              let host = comps.host
        else { return nil }
        let trimmed = thumb.replacingOccurrences(of: "/thumbnail.jpg", with: "")
        if let trimmedComps = URLComponents(string: trimmed), let path = Optional(trimmedComps.path),
           !path.isEmpty
        {
            return URL(string: "https://\(host)\(path)/playlist.m3u8")
        }
        return nil
    }
}

nonisolated struct VideosResponse: Codable {
    let items: [GalleryVideo]
    let totalCount: Int
    let page: Int
    let pageSize: Int
}
