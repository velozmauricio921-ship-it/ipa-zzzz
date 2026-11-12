struct FilzaCapabilities: OptionSet {
    let rawValue: UInt16

    static let browsing = FilzaCapabilities(rawValue: 1 << 0)
    static let reading = FilzaCapabilities(rawValue: 1 << 1)
    static let writing = FilzaCapabilities(rawValue: 1 << 2)
    static let preview = FilzaCapabilities(rawValue: 1 << 3)
    static let sharing = FilzaCapabilities(rawValue: 1 << 4)
    static let archiveHandling = FilzaCapabilities(rawValue: 1 << 5)
}
