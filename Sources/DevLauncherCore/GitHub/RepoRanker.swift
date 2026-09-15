import Foundation

public enum RepoRanker {
  private static let maximumRecommendationDistance = 3

  public static func mostRecentlyUpdated(
    _ repositories: [GitHubRepository], limit: Int? = nil
  ) -> [GitHubRepository] {
    let sorted = repositories.sorted {
      if $0.pushedAt != $1.pushedAt {
        return ($0.pushedAt ?? .distantPast) > ($1.pushedAt ?? .distantPast)
      }
      return $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending
    }
    guard let limit else { return sorted }
    return Array(sorted.prefix(max(0, limit)))
  }

  /// 对指定编号，按最新 PR 编号的绝对距离排序；等距时再结合使用历史、推送时间和名称。
  /// 只有距离足够近的首位候选才应显示为推荐。
  public static func rank(
    _ repositories: [GitHubRepository],
    history: [HistoryEntry],
    referenceNumber: Int? = nil
  ) -> [GitHubRepository] {
    let lastUse = Dictionary(
      history.compactMap { entry -> (String, Date)? in
        guard let repo = entry.repo else { return nil }
        return (repo, entry.openedAt)
      },
      uniquingKeysWith: { max($0, $1) }
    )
    return repositories.sorted { lhs, rhs in
      if let referenceNumber {
        let leftDistance = recommendationDistance(lhs, referenceNumber: referenceNumber)
        let rightDistance = recommendationDistance(rhs, referenceNumber: referenceNumber)
        if leftDistance != rightDistance { return leftDistance < rightDistance }
      }
      let leftUse = lastUse[lhs.nameWithOwner]
      let rightUse = lastUse[rhs.nameWithOwner]
      if leftUse != rightUse { return (leftUse ?? .distantPast) > (rightUse ?? .distantPast) }
      if lhs.pushedAt != rhs.pushedAt {
        return (lhs.pushedAt ?? .distantPast) > (rhs.pushedAt ?? .distantPast)
      }
      return lhs.nameWithOwner.localizedCaseInsensitiveCompare(rhs.nameWithOwner) == .orderedAscending
    }
  }

  public static func isRecommended(_ repository: GitHubRepository, for referenceNumber: Int) -> Bool {
    recommendationDistance(repository, referenceNumber: referenceNumber)
      <= maximumRecommendationDistance
  }

  private static func recommendationDistance(
    _ repository: GitHubRepository,
    referenceNumber: Int
  ) -> Int {
    guard let latest = repository.latestPullRequestNumber else {
      return Int.max
    }
    if latest >= referenceNumber { return latest - referenceNumber }
    return referenceNumber - latest
  }
}
