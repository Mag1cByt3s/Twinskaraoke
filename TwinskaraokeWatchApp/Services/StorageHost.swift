import Foundation

enum StorageHost {
  static var api: String {
    isChinaRegion ? "https://api.neurokaraoke.com.cn" : "https://api.neurokaraoke.com"
  }
  static var base: String {
    isChinaRegion ? "https://storage.neurokaraoke.com.cn" : "https://storage.neurokaraoke.com"
  }
  static var images: String {
    isChinaRegion ? "https://images.neurokaraoke.com.cn" : "https://images.neurokaraoke.com"
  }
  private static var isChinaRegion: Bool {
    if let override = UserDefaults.standard.string(forKey: "nk.storageRegion") {
      return override == "cn"
    }
    let region: String
    if #available(watchOS 9.0, *) {
      region = Locale.current.region?.identifier ?? Locale.current.identifier
    } else {
      region = Locale.current.regionCode ?? Locale.current.identifier
    }
    return region.uppercased() == "CN"
  }
}
