extension WMFContentGroupKind {
    public var eventLoggingLabel: EventLoggingLabel? {
        switch self {
        case .featuredArticle:
            return .featuredArticle
        case .topRead:
            return .topRead
        case .onThisDay:
            return .onThisDay
        case .random:
            return .random
        case .news:
            return .news
        case .relatedPages:
            return .relatedPages
        case .locationPlaceholder:
            fallthrough
        case .location:
            return .location
        default:
            return nil
        }
    }
}

