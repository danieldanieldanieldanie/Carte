import Foundation

public struct CardSide: Codable, Hashable, Sendable {
    public let index: Index
    public let content: Content

    public init(index: Index, content: Content) {
        self.index = index
        self.content = content
    }
}

public extension CardSide {
    enum Index: Int, Codable, Sendable {
        case front = 0
        case back = 1
    }

    enum Content: Codable, Hashable, Sendable {
        case text(String)
        case photo(assetID: String)
        case drawing(assetID: String)
    }
}
