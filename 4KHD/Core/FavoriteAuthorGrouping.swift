import Foundation

/// 收藏列表按作者聚合时的一个分组。
struct FavoriteAuthorGroup: Identifiable {
    let author: String
    let items: [GalleryItem]

    var id: String { author.lowercased() }
}

/// 启发式作者名抽取 —— 标题里的前缀 token、`[xxx]` 标签等综合分析，挑出最像作者的字段。
/// 纯算法，跟 UI 解耦，方便单元测试。
enum FavoriteAuthorNameParser {
    static func group(_ items: [GalleryItem]) -> [String: [GalleryItem]] {
        let itemCandidates = items.map { item in
            (item: item, candidates: authorCandidates(for: item))
        }
        let candidateCounts = Dictionary(
            itemCandidates.flatMap(\.candidates).map { ($0.key, 1) },
            uniquingKeysWith: +
        )
        let displayCounts = Dictionary(
            itemCandidates.flatMap(\.candidates).map { ("\($0.key)\u{1F}\($0.display)", 1) },
            uniquingKeysWith: +
        )

        let keyedGroups = Dictionary(grouping: itemCandidates) { pair in
            bestRepeatedCandidate(in: pair.candidates, counts: candidateCounts)?.key
                ?? pair.candidates.first?.key
                ?? canonicalKey("未知作者")
        }

        var result: [String: [GalleryItem]] = [:]
        for (key, pairs) in keyedGroups {
            let display = bestDisplayName(for: key, candidates: pairs.flatMap(\.candidates), displayCounts: displayCounts)
            result[display, default: []].append(contentsOf: pairs.map(\.item))
        }
        return result
    }

    private struct AuthorCandidate: Hashable {
        let display: String
        let key: String
    }

    private static func authorCandidates(for item: GalleryItem) -> [AuthorCandidate] {
        let source = item.rawTitle.isEmpty ? item.title : item.rawTitle
        let cleaned = removeMetadata(from: source)
        let titleWithoutLeadingTags = removeLeadingCatalogCode(from: removeLeadingBracketTags(from: cleaned))
        var candidates: [String] = []

        if titleWithoutLeadingTags.isEmpty,
           let bracketAuthor = firstMatch(#"^\s*\[([^\]]+)\]"#, in: cleaned) {
            candidates.append(normalized(bracketAuthor))
        }

        candidates.append(contentsOf: separatorCandidates(from: titleWithoutLeadingTags))
        candidates.append(contentsOf: tokenPrefixCandidates(from: titleWithoutLeadingTags))

        return unique(candidates.map(makeCandidate).filter { !$0.key.isEmpty })
    }

    private static func bestRepeatedCandidate(in candidates: [AuthorCandidate], counts: [String: Int]) -> AuthorCandidate? {
        candidates
            .filter { (counts[$0.key] ?? 0) > 1 }
            .sorted { lhs, rhs in
                let lhsCount = counts[lhs.key] ?? 0
                let rhsCount = counts[rhs.key] ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                if lhs.display.count != rhs.display.count {
                    return lhs.display.count > rhs.display.count
                }
                return lhs.display.localizedStandardCompare(rhs.display) == .orderedAscending
            }
            .first
    }

    private static func bestDisplayName(
        for key: String,
        candidates: [AuthorCandidate],
        displayCounts: [String: Int]
    ) -> String {
        candidates
            .filter { $0.key == key }
            .map(\.display)
            .sorted { lhs, rhs in
                let lhsCount = displayCounts["\(key)\u{1F}\(lhs)"] ?? 0
                let rhsCount = displayCounts["\(key)\u{1F}\(rhs)"] ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .first ?? "未知作者"
    }

    private static func separatorCandidates(from value: String) -> [String] {
        let separators = [" - ", " – ", " — ", " | ", " / ", "：", ": "]
        return separators.compactMap { separator in
            guard let range = value.range(of: separator) else { return nil }
            let prefix = String(value[..<range.lowerBound])
            return normalized(prefix)
        }
    }

    private static func tokenPrefixCandidates(from value: String) -> [String] {
        let tokens = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return ["未知作者"] }

        var kept: [String] = []
        for token in tokens.prefix(4) {
            let cleanedToken = token.trimmingCharacters(in: CharacterSet(charactersIn: ",，.。()（）[]【】"))
            guard !cleanedToken.isEmpty else { continue }
            if isSeparatorToken(cleanedToken) || isLikelySeriesToken(cleanedToken) {
                break
            }
            kept.append(cleanedToken)
            if cleanedToken.contains("(") || cleanedToken.contains("（") {
                break
            }
        }

        let usableTokens = kept.isEmpty ? [tokens[0]] : kept
        return (1...usableTokens.count).map { index in
            normalized(usableTokens.prefix(index).joined(separator: " "))
        }
    }

    private static func removeMetadata(from value: String) -> String {
        value
            .replacingOccurrences(of: #"\[[^\]]*-\d+photos\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLeadingBracketTags(from value: String) -> String {
        value
            .replacingOccurrences(of: #"^\s*(?:\[[^\]]+\]\s*)+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLeadingCatalogCode(from value: String) -> String {
        value
            .replacingOccurrences(
                of: #"^\s*(?:[._#-]*\d+(?:\.\d+)?|Vol\.?\s*\d+|No\.?\s*\d+|Part\s*\d+)\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSeparatorToken(_ token: String) -> Bool {
        ["-", "–", "—", "|", "/", ":", "："].contains(token)
    }

    private static func isLikelySeriesToken(_ token: String) -> Bool {
        token.range(of: #"^(Vol\.?\d*|No\.?\d*|Part\d*|Photo|Photos|写真|圖集|图集|Collection|Set|COS|Cosplay)$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || token.range(of: #"^\d+$"#, options: .regularExpression) != nil
    }

    private nonisolated static func makeCandidate(_ value: String) -> AuthorCandidate {
        let display = normalized(value)
        return AuthorCandidate(display: display, key: canonicalKey(display))
    }

    private nonisolated static func canonicalKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}]+"#, with: "", options: .regularExpression)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        let result = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "未知作者" : result
    }

    private static func unique(_ values: [AuthorCandidate]) -> [AuthorCandidate] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.key).inserted }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
