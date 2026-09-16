import Foundation

public enum RepositoryCachePolicy: Sendable {
  case useCache
  case reloadIgnoringCache
}

public enum RepositoryRefreshSchedule {
  public static let interval: TimeInterval = 24 * 60 * 60

  public static func delay(lastAttemptAt: Date?, now: Date) -> TimeInterval {
    guard let lastAttemptAt else { return 0 }
    return max(0, interval - now.timeIntervalSince(lastAttemptAt))
  }
}

public struct GitHubRepository: Codable, Equatable, Sendable, Identifiable {
  public var nameWithOwner: String
  public var pushedAt: Date?
  public var latestPullRequestNumber: Int?
  public var ownerLogin: String
  public var ownerIsOrganization: Bool
  public var accountIDs: [String]

  public var id: String { nameWithOwner }

  public init(
    nameWithOwner: String,
    pushedAt: Date? = nil,
    latestPullRequestNumber: Int? = nil,
    ownerLogin: String? = nil,
    ownerIsOrganization: Bool = false,
    accountIDs: [String] = []
  ) {
    self.nameWithOwner = nameWithOwner
    self.pushedAt = pushedAt
    self.latestPullRequestNumber = latestPullRequestNumber
    self.ownerLogin = ownerLogin ?? nameWithOwner.split(separator: "/").first.map(String.init) ?? ""
    self.ownerIsOrganization = ownerIsOrganization
    self.accountIDs = accountIDs
  }
}

public struct GitHubOrganization: Codable, Equatable, Sendable, Identifiable {
  public var accountID: String
  public var login: String
  public var name: String?

  public var id: String { "\(accountID)|\(login)" }

  public init(accountID: String, login: String, name: String? = nil) {
    self.accountID = accountID
    self.login = login
    self.name = name
  }
}

public struct RepositorySnapshot: Codable, Equatable, Sendable {
  public static let currentMetadataVersion = 3
  public var metadataVersion: Int?
  public var repositories: [GitHubRepository]
  public var accounts: [String]
  public var organizations: [GitHubOrganization]
  public var fetchedAt: Date
  public var selectedRefreshAttemptedAt: Date?
  public var selectedRefreshSucceededAt: Date?

  public init(
    repositories: [GitHubRepository],
    accounts: [String],
    organizations: [GitHubOrganization] = [],
    fetchedAt: Date,
    selectedRefreshAttemptedAt: Date? = nil,
    selectedRefreshSucceededAt: Date? = nil,
    metadataVersion: Int? = RepositorySnapshot.currentMetadataVersion
  ) {
    self.metadataVersion = metadataVersion
    self.repositories = repositories
    self.accounts = accounts
    self.organizations = organizations
    self.fetchedAt = fetchedAt
    self.selectedRefreshAttemptedAt = selectedRefreshAttemptedAt
    self.selectedRefreshSucceededAt = selectedRefreshSucceededAt
  }
}

public struct SelectedRepositoryRefreshResult: Equatable, Sendable {
  public var snapshot: RepositorySnapshot
  public var failedRepositories: [String]

  public init(snapshot: RepositorySnapshot, failedRepositories: [String] = []) {
    self.snapshot = snapshot
    self.failedRepositories = failedRepositories
  }
}

public protocol RepositoryProvider: Sendable {
  func cachedRepositories() -> RepositorySnapshot?
  func repositories(policy: RepositoryCachePolicy) async throws -> RepositorySnapshot
  func refreshSelectedRepositories(_ names: Set<String>) async throws
    -> SelectedRepositoryRefreshResult
}

public enum RepositoryProviderFailure: Error, Equatable, Sendable {
  case ghUnavailable
  case authenticationUnavailable(String)
  case commandFailed(String)
  case malformedResponse(String)
}

/// 通过本机 `gh` 获取当前可访问仓库。凭据只作为子进程环境变量使用，不进入缓存。
public struct GitHubRepositoryProvider: RepositoryProvider {
  public static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60
  public static let accountQuery = """
    query {
      viewer {
        login
        organizations(first: 100) {
          nodes { login name }
        }
      }
    }
    """

  public static let repositoryQuery = """
    query($owner: String!, $endCursor: String) {
      repositoryOwner(login: $owner) {
        __typename
        login
        repositories(
          first: 100
          after: $endCursor
          orderBy: {field: PUSHED_AT, direction: DESC}
          isArchived: false
        ) {
          nodes {
            nameWithOwner
            pushedAt
            pullRequests(last: 1, orderBy: {field: CREATED_AT, direction: ASC}) {
              nodes { number }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

  public static let selectedRepositoryQuery = """
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        nameWithOwner
        pushedAt
        pullRequests(last: 1, orderBy: {field: CREATED_AT, direction: ASC}) {
          nodes { number }
        }
      }
    }
    """

  private let runner: any CommandRunner
  private let fileSystem: any FileSystem
  private let clock: any Clock
  private let ghPathResolver: GhPathResolver
  private let cachePath: String

  public init(
    runner: any CommandRunner,
    fileSystem: any FileSystem,
    clock: any Clock,
    loginShell: String,
    cachePath: String
  ) {
    self.runner = runner
    self.fileSystem = fileSystem
    self.clock = clock
    self.ghPathResolver = GhPathResolver(
      runner: runner, fileSystem: fileSystem, loginShell: loginShell)
    self.cachePath = cachePath
  }

  public func cachedRepositories() -> RepositorySnapshot? {
    loadCache()
  }

  public func repositories(policy: RepositoryCachePolicy) async throws -> RepositorySnapshot {
    let cached = loadCache()
    if policy == .useCache, let cached,
      clock.now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime
    {
      return cached
    }

    do {
      return try fetchRepositories()
    } catch {
      if let cached { return cached }
      throw error
    }
  }

  public func refreshSelectedRepositories(_ names: Set<String>) async throws
    -> SelectedRepositoryRefreshResult
  {
    let cached = loadCache()
    let now = clock.now
    var snapshot = cached ?? RepositorySnapshot(
      repositories: [], accounts: [], fetchedAt: now)
    snapshot.selectedRefreshAttemptedAt = now

    let sortedNames = names.sorted()
    guard !sortedNames.isEmpty else {
      snapshot.selectedRefreshSucceededAt = now
      snapshot.fetchedAt = now
      try saveCache(snapshot)
      return SelectedRepositoryRefreshResult(snapshot: snapshot)
    }

    do {
      guard let gh = ghPathResolver.resolve() else {
        throw RepositoryProviderFailure.ghUnavailable
      }
      let accounts = try authenticatedAccounts(gh: gh)
      guard !accounts.isEmpty else {
        throw RepositoryProviderFailure.authenticationUnavailable("GitHub CLI 尚未登录")
      }
      let contexts = try accounts.compactMap { account -> AccountContext? in
        let tokenResult = try runner.run(
          executable: gh,
          arguments: ["auth", "token", "--hostname", account.host, "--user", account.login],
          environment: nil,
          timeoutSeconds: 20
        )
        let token = tokenResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tokenResult.exitCode == 0, !token.isEmpty else { return nil }
        return AccountContext(account: account, token: token)
      }
      guard !contexts.isEmpty else {
        throw RepositoryProviderFailure.authenticationUnavailable("GitHub CLI 尚未返回可用凭据")
      }

      var updates: [String: GitHubRepository] = [:]
      var failed: [String] = []
      let cachedByName = Dictionary(uniqueKeysWithValues: snapshot.repositories.map {
        ($0.nameWithOwner, $0)
      })

      for nameWithOwner in sortedNames {
        let components = nameWithOwner.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
          failed.append(nameWithOwner)
          continue
        }
        let owner = components[0]
        let name = components[1]
        let existing = cachedByName[nameWithOwner]
        let preferredAccountIDs = Set(existing?.accountIDs ?? [])
        let preferredContexts = contexts.filter {
          preferredAccountIDs.contains($0.account.id)
        }
        let eligibleContexts = preferredContexts.isEmpty ? contexts : preferredContexts

        var refreshed: GitHubRepository?
        for context in eligibleContexts {
          guard let result = try? runner.run(
            executable: gh,
            arguments: [
              "api", "graphql", "--hostname", context.account.host,
              "-F", "owner=\(owner)", "-F", "name=\(name)",
              "-f", "query=\(Self.selectedRepositoryQuery)",
            ],
            environment: ["GH_TOKEN": context.token, "GH_HOST": context.account.host],
            timeoutSeconds: 30
          ), result.exitCode == 0,
            var repository = try? Self.parseSelectedRepository(result.stdout)
          else { continue }

          repository.ownerLogin = existing?.ownerLogin ?? owner
          repository.ownerIsOrganization = existing?.ownerIsOrganization
            ?? (owner.caseInsensitiveCompare(context.account.login) != .orderedSame)
          repository.accountIDs = Array(
            Set((existing?.accountIDs ?? []) + [context.account.id])
          ).sorted()
          refreshed = repository
          break
        }

        if let refreshed {
          updates[nameWithOwner] = refreshed
        } else {
          failed.append(nameWithOwner)
        }
      }

      let existingNames = Set(snapshot.repositories.map(\.nameWithOwner))
      snapshot.repositories = snapshot.repositories.map { updates[$0.nameWithOwner] ?? $0 }
      snapshot.repositories.append(contentsOf: sortedNames.compactMap { name in
        existingNames.contains(name) ? nil : updates[name]
      })
      if !updates.isEmpty { snapshot.fetchedAt = now }
      if failed.isEmpty { snapshot.selectedRefreshSucceededAt = now }
      try saveCache(snapshot)
      return SelectedRepositoryRefreshResult(
        snapshot: snapshot, failedRepositories: failed.sorted())
    } catch {
      guard cached != nil else { throw error }
      try saveCache(snapshot)
      return SelectedRepositoryRefreshResult(
        snapshot: snapshot, failedRepositories: sortedNames)
    }
  }

  private func fetchRepositories() throws -> RepositorySnapshot {
    guard let gh = ghPathResolver.resolve() else { throw RepositoryProviderFailure.ghUnavailable }
    let accounts = try authenticatedAccounts(gh: gh)
    guard !accounts.isEmpty else {
      throw RepositoryProviderFailure.authenticationUnavailable("GitHub CLI 尚未登录")
    }

    var byName: [String: GitHubRepository] = [:]
    var organizationsByID: [String: GitHubOrganization] = [:]
    for account in accounts {
      let tokenResult = try runner.run(
        executable: gh,
        arguments: ["auth", "token", "--hostname", account.host, "--user", account.login],
        environment: nil,
        timeoutSeconds: 20
      )
      let token = tokenResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      guard tokenResult.exitCode == 0, !token.isEmpty else { continue }

      let metadataResult = try runner.run(
        executable: gh,
        arguments: ["api", "graphql", "--hostname", account.host, "-f", "query=\(Self.accountQuery)"],
        environment: ["GH_TOKEN": token, "GH_HOST": account.host],
        timeoutSeconds: 30
      )
      guard metadataResult.exitCode == 0,
        let metadata = try? Self.parseAccountMetadata(metadataResult.stdout, accountID: account.id)
      else { continue }

      for organization in metadata.organizations {
        organizationsByID[organization.id] = organization
      }
      let owners = [(metadata.login, false)] + metadata.organizations.map { ($0.login, true) }
      for (owner, isOrganization) in owners {
        let result = try runner.run(
          executable: gh,
          arguments: [
            "api", "graphql", "--hostname", account.host, "--paginate", "--slurp",
            "-F", "owner=\(owner)", "-f", "query=\(Self.repositoryQuery)",
          ],
          environment: ["GH_TOKEN": token, "GH_HOST": account.host],
          timeoutSeconds: 30
        )
        guard result.exitCode == 0 else { continue }
        for var repository in try Self.parseRepositories(result.stdout) {
          repository.ownerLogin = owner
          repository.ownerIsOrganization = isOrganization
          repository.accountIDs = [account.id]
          if let existing = byName[repository.nameWithOwner] {
            repository.accountIDs = Array(Set(existing.accountIDs + repository.accountIDs)).sorted()
            if (existing.pushedAt ?? .distantPast) > (repository.pushedAt ?? .distantPast) {
              repository.pushedAt = existing.pushedAt
            }
            repository.latestPullRequestNumber = [
              existing.latestPullRequestNumber, repository.latestPullRequestNumber,
            ].compactMap { $0 }.max()
            byName[repository.nameWithOwner] = repository
          } else {
            byName[repository.nameWithOwner] = repository
          }
        }
      }
    }

    guard !byName.isEmpty else {
      throw RepositoryProviderFailure.commandFailed("没有读取到可访问的仓库")
    }
    let snapshot = RepositorySnapshot(
      repositories: Array(byName.values),
      accounts: accounts.map(\.id).sorted(),
      organizations: Array(organizationsByID.values).sorted {
        if $0.accountID != $1.accountID { return $0.accountID < $1.accountID }
        return $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending
      },
      fetchedAt: clock.now,
      selectedRefreshAttemptedAt: clock.now,
      selectedRefreshSucceededAt: clock.now
    )
    try saveCache(snapshot)
    return snapshot
  }

  private struct Account: Equatable {
    var host: String
    var login: String
    var id: String { "\(login)@\(host)" }
  }

  private struct AccountContext {
    var account: Account
    var token: String
  }

  private struct AccountAPIResponse: Decodable {
    struct DataNode: Decodable {
      struct Viewer: Decodable {
        struct Organization: Decodable {
          var login: String
          var name: String?
        }
        struct Organizations: Decodable { var nodes: [Organization] }
        var login: String
        var organizations: Organizations
      }
      var viewer: Viewer
    }
    var data: DataNode
  }

  private struct AccountMetadata {
    var login: String
    var organizations: [GitHubOrganization]
  }

  private static func parseAccountMetadata(_ output: String, accountID: String) throws
    -> AccountMetadata
  {
    do {
      let response = try JSONDecoder().decode(AccountAPIResponse.self, from: Data(output.utf8))
      return AccountMetadata(
        login: response.data.viewer.login,
        organizations: response.data.viewer.organizations.nodes.map {
          GitHubOrganization(accountID: accountID, login: $0.login, name: $0.name)
        }
      )
    } catch {
      throw RepositoryProviderFailure.malformedResponse("无法解析 GitHub 账号与组织")
    }
  }

  private struct AuthStatus: Decodable {
    struct Entry: Decodable {
      var state: String
      var host: String
      var login: String
    }
    var hosts: [String: [Entry]]
  }

  private func authenticatedAccounts(gh: String) throws -> [Account] {
    let result = try runner.run(
      executable: gh,
      arguments: ["auth", "status", "--json", "hosts"],
      environment: nil,
      timeoutSeconds: 20
    )
    guard result.exitCode == 0 else {
      throw RepositoryProviderFailure.authenticationUnavailable(result.stderr)
    }
    do {
      let status = try JSONDecoder().decode(AuthStatus.self, from: Data(result.stdout.utf8))
      return status.hosts.values.flatMap { $0 }
        .filter { $0.state == "success" }
        .map { Account(host: $0.host, login: $0.login) }
    } catch {
      throw RepositoryProviderFailure.malformedResponse("无法解析 gh 登录状态")
    }
  }

  private struct APIPage: Decodable {
    struct DataNode: Decodable {
      struct RepositoryOwner: Decodable {
        struct Repositories: Decodable {
          struct Node: Decodable {
            struct PullRequests: Decodable {
              struct PullRequest: Decodable { var number: Int }
              var nodes: [PullRequest]
            }
            var nameWithOwner: String
            var pushedAt: Date?
            var pullRequests: PullRequests
          }
          var nodes: [Node]
        }
        var repositories: Repositories
      }
      var repositoryOwner: RepositoryOwner?
    }
    var data: DataNode
  }

  private struct SelectedRepositoryAPIResponse: Decodable {
    struct DataNode: Decodable {
      struct Repository: Decodable {
        struct PullRequests: Decodable {
          struct PullRequest: Decodable { var number: Int }
          var nodes: [PullRequest]
        }
        var nameWithOwner: String
        var pushedAt: Date?
        var pullRequests: PullRequests
      }
      var repository: Repository?
    }
    var data: DataNode
  }

  private struct LegacyAPIRepository: Decodable {
    var fullName: String
    var pushedAt: Date?
    var archived: Bool

    enum CodingKeys: String, CodingKey {
      case fullName = "full_name"
      case pushedAt = "pushed_at"
      case archived
    }
  }

  public static func parseRepositories(_ output: String) throws -> [GitHubRepository] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      let pages = try decoder.decode([APIPage].self, from: Data(output.utf8))
      return pages.compactMap { $0.data.repositoryOwner?.repositories.nodes }.flatMap { $0 }.map {
        GitHubRepository(
          nameWithOwner: $0.nameWithOwner,
          pushedAt: $0.pushedAt,
          latestPullRequestNumber: $0.pullRequests.nodes.last?.number
        )
      }
    } catch {
      // 兼容节点 4 已写入的 REST 形状缓存测试与旧 CLI 输出。
      if let pages = try? decoder.decode([[LegacyAPIRepository]].self, from: Data(output.utf8)) {
        return pages.flatMap { $0 }.filter { !$0.archived }.map {
          GitHubRepository(nameWithOwner: $0.fullName, pushedAt: $0.pushedAt)
        }
      }
      throw RepositoryProviderFailure.malformedResponse("无法解析 gh 仓库与最新 PR 编号")
    }
  }

  public static func parseSelectedRepository(_ output: String) throws -> GitHubRepository? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      guard let repository = try decoder.decode(
        SelectedRepositoryAPIResponse.self, from: Data(output.utf8)
      ).data.repository else { return nil }
      return GitHubRepository(
        nameWithOwner: repository.nameWithOwner,
        pushedAt: repository.pushedAt,
        latestPullRequestNumber: repository.pullRequests.nodes.last?.number
      )
    } catch {
      throw RepositoryProviderFailure.malformedResponse("无法解析已勾选仓库的最新 PR 编号")
    }
  }

  private func loadCache() -> RepositorySnapshot? {
    guard fileSystem.fileExists(atPath: cachePath),
      let data = try? fileSystem.read(atPath: cachePath)
    else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let snapshot = try? decoder.decode(RepositorySnapshot.self, from: data),
      snapshot.metadataVersion == RepositorySnapshot.currentMetadataVersion
    else { return nil }
    return snapshot
  }

  private func saveCache(_ snapshot: RepositorySnapshot) throws {
    let parent = (cachePath as NSString).deletingLastPathComponent
    try fileSystem.createDirectory(atPath: parent)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try fileSystem.write(try encoder.encode(snapshot), toPath: cachePath)
  }
}
