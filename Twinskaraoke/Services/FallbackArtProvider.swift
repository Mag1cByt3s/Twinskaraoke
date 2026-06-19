import Combine
import Foundation

nonisolated struct FallbackArt: Sendable {
  let url: URL
  let artistName: String?
  let artistLink: String?
}

nonisolated final class FallbackArtProvider: ObservableObject, @unchecked Sendable {
  static let shared = FallbackArtProvider()

  private var items: [FallbackArtItem] = []
  private var cache: [String: FallbackArt] = [:]
  private let lock = NSLock()
  private let persistKey = "nk.fallbackArtCache"

  private init() {
    loadPersistedCache()
    fetch()
  }

  func art(for id: String) -> FallbackArt? {
    lock.lock()
    if let cached = cache[id] {
      if let repaired = repairedBindingIfNeeded(for: id, cached: cached) {
        lock.unlock()
        return repaired
      }
      lock.unlock()
      return cached
    }
    if items.isEmpty {
      if let persisted = loadPersistedEntry(for: id) {
        if isPersistedDuplicateWithoutReplacement(for: id, art: persisted) {
          cache.removeValue(forKey: id)
          removePersistedEntry(id: id)
          lock.unlock()
          return nil
        }
        if let repaired = repairedBindingIfNeeded(for: id, cached: persisted) {
          lock.unlock()
          return repaired
        }
        assign(persisted, to: id)
        lock.unlock()
        return persisted
      }
      lock.unlock()
      return nil
    }
    guard let item = nextItem(for: id) else {
      lock.unlock()
      return nil
    }
    let result = FallbackArt(url: item.url, artistName: item.artistName, artistLink: item.artistLink)
    assign(result, to: id)
    lock.unlock()
    return result
  }

  func url(for id: String) -> URL? {
    art(for: id)?.url
  }

  func resetBindings() {
    lock.lock()
    cache.removeAll()
    lock.unlock()
    UserDefaults.standard.removeObject(forKey: persistKey)
  }

  var randomURL: URL? {
    lock.lock()
    defer { lock.unlock() }
    if !items.isEmpty {
      return items[Int.random(in: 0..<items.count)].url
    }
    // Cold start: the validated pool hasn't been fetched yet. Fall back to a
    // real image URL previously assigned to a song (persisted across launches)
    // so the hero/genre artwork can still load instead of trying to render the
    // JSON random-art endpoint as an image.
    return cache.values.map(\.url).randomElement()
  }

  private static func stableHash(_ string: String) -> Int {
    var hash: UInt64 = 5381
    for byte in string.utf8 {
      hash = hash &* 33 &+ UInt64(byte)
    }
    return Int(hash % UInt64(Int.max))
  }

  private func repairedBindingIfNeeded(for id: String, cached: FallbackArt) -> FallbackArt? {
    guard !items.isEmpty else {
      cache[id] = cached
      return nil
    }
    let availableURLs = Set(items.map { $0.url })
    let staleBinding = !availableURLs.contains(cached.url)
    let usedByOtherSong = cache.contains { otherID, otherArt in
      otherID != id && otherArt.url == cached.url
    }
    guard staleBinding || usedByOtherSong else {
      cache[id] = cached
      return nil
    }
    guard let item = nextItem(for: id, excludingID: id) else {
      cache.removeValue(forKey: id)
      removePersistedEntry(id: id)
      return nil
    }
    let replacement = FallbackArt(url: item.url, artistName: item.artistName, artistLink: item.artistLink)
    assign(replacement, to: id)
    return replacement
  }

  private func nextItem(for id: String, excludingID: String? = nil) -> FallbackArtItem? {
    guard !items.isEmpty else { return nil }
    let availableURLs = Set(items.map { $0.url })
    let used = Set(
      cache.compactMap { entry -> URL? in
        if entry.key == excludingID { return nil }
        return availableURLs.contains(entry.value.url) ? entry.value.url : nil
      })
    let start = Self.stableHash(id) % items.count
    for offset in 0..<items.count {
      let item = items[(start + offset) % items.count]
      if !used.contains(item.url) {
        return item
      }
    }
    return items[start]
  }

  private func isPersistedDuplicateWithoutReplacement(for id: String, art: FallbackArt) -> Bool {
    items.isEmpty
      && cache.contains { otherID, otherArt in
        otherID != id && otherArt.url == art.url
      }
  }

  private func assign(_ art: FallbackArt, to id: String) {
    cache[id] = art
    persistEntry(id: id, url: art.url, artistName: art.artistName, artistLink: art.artistLink)
  }

  private func loadPersistedCache() {
    guard let dict = UserDefaults.standard.dictionary(forKey: persistKey) as? [String: [String: String]] else { return }
    var usedURLs = Set<URL>()
    var cleaned = dict
    for (id, entry) in dict {
      guard let urlStr = entry["url"], let url = URL(string: urlStr) else {
        cleaned.removeValue(forKey: id)
        continue
      }
      guard !usedURLs.contains(url) else {
        cleaned.removeValue(forKey: id)
        continue
      }
      usedURLs.insert(url)
      cache[id] = FallbackArt(url: url, artistName: entry["artistName"], artistLink: entry["artistLink"])
    }
    if cleaned.count != dict.count {
      UserDefaults.standard.set(cleaned, forKey: persistKey)
    }
  }

  private func loadPersistedEntry(for id: String) -> FallbackArt? {
    guard let dict = UserDefaults.standard.dictionary(forKey: persistKey) as? [String: [String: String]],
      let entry = dict[id],
      let urlStr = entry["url"],
      let url = URL(string: urlStr)
    else { return nil }
    return FallbackArt(url: url, artistName: entry["artistName"], artistLink: entry["artistLink"])
  }

  private func persistEntry(id: String, url: URL, artistName: String?, artistLink: String?) {
    var dict = (UserDefaults.standard.dictionary(forKey: persistKey) as? [String: [String: String]]) ?? [:]
    var entry: [String: String] = ["url": url.absoluteString]
    if let name = artistName { entry["artistName"] = name }
    if let link = artistLink { entry["artistLink"] = link }
    dict[id] = entry
    UserDefaults.standard.set(dict, forKey: persistKey)
  }

  private func removePersistedEntry(id: String) {
    var dict = (UserDefaults.standard.dictionary(forKey: persistKey) as? [String: [String: String]]) ?? [:]
    dict.removeValue(forKey: id)
    UserDefaults.standard.set(dict, forKey: persistKey)
  }

  private func fetch() {
    let fetchCount = 48
    var fetchedItems: [FallbackArtItem] = []
    let group = DispatchGroup()
    let syncQueue = DispatchQueue(label: "com.twinskaraoke.fallbackart.sync")

    for index in 0..<fetchCount {
      group.enter()
      let urlString = "\(StorageHost.api)/public/art/yuri/random?fallback=\(index)&t=\(UUID().uuidString)"
      guard let url = URL(string: urlString) else {
        group.leave()
        continue
      }
      var request = URLRequest(url: url)
      request.cachePolicy = .reloadIgnoringLocalCacheData
      request.timeoutInterval = 10
      GuestIdentity.applyIfNeeded(to: &request)
      URLSession.shared.dataTask(with: request) { data, _, _ in
        defer { group.leave() }
        guard let data = data,
              let item = try? JSONDecoder().decode(RandomArtItem.self, from: data),
              let baseURL = URL(string: item.url)
        else { return }

        let urlWithQuality = URL(string: "\(item.url)/width=480,quality=85,format=auto") ?? baseURL

        group.enter()
        var headRequest = URLRequest(url: urlWithQuality)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 10
        URLSession.shared.dataTask(with: headRequest) { _, response, error in
          defer { group.leave() }
          guard error == nil,
                let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode)
          else { return }

          let fallbackItem = FallbackArtItem(url: urlWithQuality, artistName: item.artistCredit, artistLink: nil)
          syncQueue.sync {
            fetchedItems.append(fallbackItem)
          }
        }.resume()
      }.resume()
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      let uniqueItems = fetchedItems.reduce(into: [FallbackArtItem]()) { result, item in
        guard !result.contains(where: { $0.url == item.url }) else { return }
        result.append(item)
      }
      self.lock.lock()
      self.items = uniqueItems
      self.repairDuplicateBindings()
      self.lock.unlock()
      // Notify observers so views that resolved a nil fallback URL before the
      // pool was ready (song.imageURL / randomURL) re-render and pick it up.
      self.objectWillChange.send()
    }
  }

  private func repairDuplicateBindings() {
    guard !items.isEmpty else { return }
    let availableURLs = Set(items.map { $0.url })
    var used = Set<URL>()
    for id in cache.keys.sorted() {
      guard let art = cache[id] else { continue }
      if availableURLs.contains(art.url), !used.contains(art.url) {
        used.insert(art.url)
        continue
      }
      cache.removeValue(forKey: id)
      guard let item = nextItem(for: id) else {
        removePersistedEntry(id: id)
        continue
      }
      let replacement = FallbackArt(url: item.url, artistName: item.artistName, artistLink: item.artistLink)
      assign(replacement, to: id)
      used.insert(replacement.url)
    }
  }
}

nonisolated private struct FallbackArtItem: Sendable {
  let url: URL
  let artistName: String?
  let artistLink: String?
}

nonisolated private struct RandomArtItem: Decodable {
  let url: String
  let artistCredit: String?
}
