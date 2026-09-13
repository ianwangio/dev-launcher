import DevLauncherCore
import SwiftUI

struct IntegrationsView: View {
  @Bindable var model: AppModel
  @State private var selection: IntegrationDestination = .github

  var body: some View {
    HSplitView {
      integrationList
        .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)

      detail
        .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var integrationList: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: UISpacing.xSmall) {
        Text("集成").font(.title2.weight(.bold))
        Text("连接常用工具并检查运行环境")
          .font(.callout).foregroundStyle(.secondary)
      }
      .padding(.horizontal, UISpacing.large)
      .padding(.top, 24)
      .padding(.bottom, UISpacing.medium)

      VStack(spacing: UISpacing.small) {
        ForEach(IntegrationDestination.allCases) { destination in
          Button { selection = destination } label: {
            HStack(spacing: UISpacing.medium) {
              UIActionIcon(icon: destination.icon, pointSize: 24)
                .frame(width: 38, height: 38)
              VStack(alignment: .leading, spacing: 3) {
                Text(destination.title).font(.callout.weight(.semibold))
                Label(statusTitle(for: destination), systemImage: "circle.fill")
                  .font(.caption)
                  .foregroundStyle(statusColor(for: destination))
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, UISpacing.medium)
            .frame(height: 66)
            .background(
              selection == destination ? Color.accentColor.opacity(0.15) : Color.clear,
              in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, UISpacing.small)
      Spacer()
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
  }

  @ViewBuilder private var detail: some View {
    switch selection {
    case .github: GitHubIntegrationDetail(model: model)
    case .linear: LinearIntegrationDetail(model: model)
    case .applications: ApplicationsIntegrationDetail(model: model)
    case .scripts: ScriptIntegrationDetail(model: model)
    }
  }

  private func statusTitle(for destination: IntegrationDestination) -> String {
    switch destination {
    case .github:
      if model.isRefreshingIntegrations { return "检测中" }
      if let snapshot = model.repositorySnapshot {
        let selected = snapshot.repositories.filter {
          model.isRepositorySelected($0.nameWithOwner)
        }.count
        return "已选 \(selected) / \(snapshot.repositories.count)"
      }
      return model.repositoryError == nil ? "等待检测" : "需要处理"
    case .linear:
      return model.settings.linearWorkspace.isEmpty || model.settings.linearTeamKeys.isEmpty
        ? "需要配置" : "已配置"
    case .applications:
      let count = model.installedApplications.filter(\.installed).count
      return "\(count) 个可用"
    case .scripts:
      let available = model.scriptEnvironments.filter(\.available).map(\.name)
      return available.isEmpty ? "需要处理" : available.joined(separator: "、") + " 可用"
    }
  }

  private func statusColor(for destination: IntegrationDestination) -> Color {
    switch destination {
    case .github: model.repositorySnapshot == nil ? .orange : .green
    case .linear:
      model.settings.linearWorkspace.isEmpty || model.settings.linearTeamKeys.isEmpty ? .orange : .green
    case .applications: model.installedApplications.contains(where: \.installed) ? .green : .orange
    case .scripts: model.scriptEnvironments.contains(where: \.available) ? .green : .orange
    }
  }
}

private enum IntegrationDestination: String, CaseIterable, Identifiable {
  case github, linear, applications, scripts
  var id: String { rawValue }
  var title: String {
    switch self {
    case .github: "GitHub"
    case .linear: "Linear"
    case .applications: "应用"
    case .scripts: "脚本环境"
    }
  }
  var icon: CandidateIcon {
    switch self {
    case .github: .application(name: "GitHub Desktop")
    case .linear: .application(name: "Linear")
    case .applications: .system(symbolName: "square.grid.2x2")
    case .scripts: .application(name: "Terminal")
    }
  }
}

private struct GitHubIntegrationDetail: View {
  @Bindable var model: AppModel
  @State private var search = ""
  @State private var selectedAccountIDs: Set<String>?
  @State private var selectedOwnerIDs: Set<String>?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: UISpacing.xLarge) {
        IntegrationHeader(
          icon: .application(name: "GitHub Desktop"),
          title: "GitHub",
          status: status,
          isHealthy: model.repositorySnapshot != nil,
          actionTitle: model.isRefreshingIntegrations ? "检测中" : "重新检测",
          action: { model.refreshIntegrations() }
        )
        Divider()

        if let error = model.repositoryError {
          IntegrationNotice(
            symbol: "exclamationmark.triangle.fill",
            color: .orange,
            title: "GitHub 暂不可用",
            detail: error + "。请先安装并执行 gh auth login。"
          )
        }

        stepHeading(1, "选择账号", "可同时选择多个本机 GitHub CLI 已登录账号。")
        if let accounts = model.repositorySnapshot?.accounts, !accounts.isEmpty {
          selectionToolbar(
            selected: effectiveAccountIDs.count,
            total: accounts.count,
            selectAll: { selectedAccountIDs = nil },
            clear: {
              selectedAccountIDs = []
              search = ""
            }
          )
          LazyVGrid(
            columns: twoColumnGrid,
            alignment: .leading,
            spacing: UISpacing.small
          ) {
            ForEach(accounts, id: \.self) { account in
              selectionButton(
                title: accountLogin(account),
                subtitle: accountHost(account),
                symbol: "person.crop.circle.fill",
                selected: effectiveAccountIDs.contains(account)
              ) {
                var selection = effectiveAccountIDs
                if selection.contains(account) { selection.remove(account) } else { selection.insert(account) }
                selectedAccountIDs = selection
                search = ""
              }
            }
          }
        } else {
          Text("尚未检测到已登录账号").font(.callout).foregroundStyle(.secondary)
        }

        Divider()
        stepHeading(2, "选择 Organization", "可同时选择多个组织；个人仓库也会单独列出。")
        if ownerChoices.isEmpty {
          Text(effectiveAccountIDs.isEmpty ? "请先选择至少一个账号" : "所选账号下没有可用的 Organization 或个人仓库")
            .font(.callout).foregroundStyle(.secondary)
        } else {
          selectionToolbar(
            selected: effectiveOwnerIDs.intersection(Set(ownerChoices.map(\.id))).count,
            total: ownerChoices.count,
            selectAll: { selectedOwnerIDs = nil },
            clear: {
              selectedOwnerIDs = []
              search = ""
            }
          )
          LazyVGrid(
            columns: twoColumnGrid,
            alignment: .leading,
            spacing: UISpacing.small
          ) {
            ForEach(ownerChoices) { owner in
              selectionButton(
                title: owner.title,
                subtitle: owner.subtitle,
                symbol: owner.isOrganization ? "building.2.fill" : "person.fill",
                selected: effectiveOwnerIDs.contains(owner.id)
              ) {
                var selection = effectiveOwnerIDs
                if selection.contains(owner.id) { selection.remove(owner.id) } else { selection.insert(owner.id) }
                selectedOwnerIDs = selection
                search = ""
              }
            }
          }
        }

        Divider()
        HStack(alignment: .firstTextBaseline) {
          stepHeading(
            3, "选择仓库",
            model.repositorySnapshot.map {
              "按最后更新时间排序 · 缓存更新于 \($0.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
            } ?? "仓库会缓存 24 小时；手动刷新会立即重新读取。"
          )
          Spacer()
          Button("刷新", systemImage: "arrow.clockwise") { model.refreshIntegrations() }
            .disabled(model.isRefreshingIntegrations)
        }
        HStack(spacing: UISpacing.small) {
          Text("当前范围已选择 \(selectedVisibleRepositoryCount) / \(visibleRepositories.count) · 全部已选 \(selectedRepositoryCount)")
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
          Spacer()
          Button("最近 10 个") {
            model.replaceRepositorySelection(
              in: visibleRepositories.map(\.nameWithOwner),
              with: Array(visibleRepositories.prefix(10)).map(\.nameWithOwner)
            )
          }
          Button("全选当前") {
            model.replaceRepositorySelection(
              in: visibleRepositories.map(\.nameWithOwner),
              with: visibleRepositories.map(\.nameWithOwner)
            )
          }
          Button("全不选当前") {
            model.replaceRepositorySelection(in: visibleRepositories.map(\.nameWithOwner), with: [])
          }
        }
        .buttonStyle(.borderless)
        TextField("搜索仓库（按名称或所有者）", text: $search)
          .textFieldStyle(.roundedBorder)

        LazyVStack(spacing: 0) {
          ForEach(filteredRepositories) { repository in
            HStack(spacing: UISpacing.medium) {
              Toggle(
                "选择 \(repository.nameWithOwner)",
                isOn: Binding(
                  get: { model.isRepositorySelected(repository.nameWithOwner) },
                  set: { model.setRepositorySelected(repository.nameWithOwner, selected: $0) }
                )
              )
              .labelsHidden().toggleStyle(.checkbox)
              UIActionIcon(icon: .application(name: "GitHub Desktop"), pointSize: 17)
                .frame(width: 24, height: 24)
              Text(repository.nameWithOwner).font(.callout.weight(.medium))
              Spacer()
              if let latest = repository.latestPullRequestNumber {
                Text("最新 PR #\(latest)")
                  .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
              }
              if let pushedAt = repository.pushedAt {
                Text("更新于 " + pushedAt.formatted(date: .abbreviated, time: .omitted))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            .padding(.horizontal, UISpacing.medium).frame(height: 38)
            if repository.id != filteredRepositories.last?.id { Divider() }
          }
        }
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

        Divider()
        HStack {
          VStack(alignment: .leading, spacing: UISpacing.xSmall) {
            Text("GitHub #N 规则").font(.headline)
            Text("复制 #123 后，先按最新 PR 编号推荐，再结合使用历史和更新时间排序。")
              .font(.callout).foregroundStyle(.secondary)
          }
          Spacer()
          Button("测试 #42", systemImage: "play.fill") { model.showPanel(for: "#42") }
            .buttonStyle(.borderedProminent)
            .disabled(model.repositorySnapshot == nil)
        }
      }
      .padding(28)
      .frame(maxWidth: 980, alignment: .leading)
    }
  }

  private var status: String {
    if model.isRefreshingIntegrations { return "正在检测 GitHub CLI、账号和仓库…" }
    if let snapshot = model.repositorySnapshot {
      return "已连接 \(snapshot.accounts.count) 个账号，可使用 \(snapshot.repositories.count) 个仓库。"
    }
    return model.repositoryError ?? "等待检测"
  }

  private var filteredRepositories: [GitHubRepository] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty
      ? visibleRepositories
      : visibleRepositories.filter {
        $0.nameWithOwner.localizedCaseInsensitiveContains(query)
      }
  }

  private var selectedRepositoryCount: Int {
    (model.repositorySnapshot?.repositories ?? []).filter {
      model.isRepositorySelected($0.nameWithOwner)
    }.count
  }

  private var selectedVisibleRepositoryCount: Int {
    visibleRepositories.filter { model.isRepositorySelected($0.nameWithOwner) }.count
  }

  private var effectiveAccountIDs: Set<String> {
    let accounts = Set(model.repositorySnapshot?.accounts ?? [])
    return (selectedAccountIDs ?? accounts).intersection(accounts)
  }

  private var ownerChoices: [OwnerChoice] {
    guard let snapshot = model.repositorySnapshot else { return [] }
    var byID: [String: OwnerChoice] = [:]
    for organization in snapshot.organizations where effectiveAccountIDs.contains(organization.accountID) {
      let id = "org|\(organization.login)"
      let update = latestUpdate(owner: organization.login, accountIDs: effectiveAccountIDs)
      if var existing = byID[id] {
        existing.accountIDs.insert(organization.accountID)
        existing.latestUpdate = [existing.latestUpdate, update].compactMap { $0 }.max()
        byID[id] = existing
      } else {
        byID[id] = OwnerChoice(
          id: id,
          login: organization.login,
          title: organization.name.flatMap { $0.isEmpty ? nil : $0 } ?? organization.login,
          subtitle: "@\(organization.login)",
          isOrganization: true,
          accountIDs: [organization.accountID],
          latestUpdate: update
        )
      }
    }
    for accountID in effectiveAccountIDs {
      let login = accountLogin(accountID)
      guard snapshot.repositories.contains(where: {
        $0.accountIDs.contains(accountID) && !$0.ownerIsOrganization && $0.ownerLogin == login
      }) else { continue }
      let id = "user|\(accountID)"
      byID[id] = OwnerChoice(
        id: id, login: login, title: "个人仓库 · \(login)",
        subtitle: "@\(login)", isOrganization: false,
        accountIDs: [accountID],
        latestUpdate: latestUpdate(owner: login, accountIDs: [accountID])
      )
    }
    return byID.values.sorted {
      if $0.latestUpdate != $1.latestUpdate {
        return ($0.latestUpdate ?? .distantPast) > ($1.latestUpdate ?? .distantPast)
      }
      return $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending
    }
  }

  private var effectiveOwnerIDs: Set<String> {
    let available = Set(ownerChoices.map(\.id))
    return (selectedOwnerIDs ?? available).intersection(available)
  }

  private var visibleRepositories: [GitHubRepository] {
    let selectedOwners = ownerChoices.filter { effectiveOwnerIDs.contains($0.id) }
    guard !effectiveAccountIDs.isEmpty, !selectedOwners.isEmpty else { return [] }
    return RepoRanker.mostRecentlyUpdated(
      (model.repositorySnapshot?.repositories ?? [])
        .filter { repository in
          !Set(repository.accountIDs).isDisjoint(with: effectiveAccountIDs)
            && selectedOwners.contains { owner in
              owner.login == repository.ownerLogin
                && owner.isOrganization == repository.ownerIsOrganization
                && !owner.accountIDs.isDisjoint(with: Set(repository.accountIDs))
            }
        }
    )
  }

  private func latestUpdate(owner: String, accountIDs: Set<String>) -> Date? {
    model.repositorySnapshot?.repositories
      .filter { !Set($0.accountIDs).isDisjoint(with: accountIDs) && $0.ownerLogin == owner }
      .compactMap(\.pushedAt)
      .max()
  }

  private func accountLogin(_ accountID: String) -> String {
    accountID.split(separator: "@").first.map(String.init) ?? accountID
  }

  private func accountHost(_ accountID: String) -> String {
    accountID.split(separator: "@").dropFirst().joined(separator: "@")
  }

  @ViewBuilder
  private func stepHeading(_ number: Int, _ title: String, _ subtitle: String) -> some View {
    HStack(alignment: .top, spacing: UISpacing.medium) {
      Text("\(number)")
        .font(.caption.weight(.bold)).foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(Color.accentColor, in: Circle())
      UISectionHeading(title: title, subtitle: subtitle)
    }
  }

  @ViewBuilder
  private func selectionButton(
    title: String,
    subtitle: String,
    symbol: String,
    selected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: UISpacing.small) {
        Image(systemName: selected ? "checkmark.square.fill" : "square")
          .foregroundStyle(selected ? Color.accentColor : .secondary)
        Image(systemName: symbol).foregroundStyle(selected ? Color.accentColor : .secondary)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.callout.weight(.semibold)).lineLimit(1)
          Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      .padding(.horizontal, UISpacing.medium).frame(height: 42)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9)
          .stroke(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func selectionToolbar(
    selected: Int,
    total: Int,
    selectAll: @escaping () -> Void,
    clear: @escaping () -> Void
  ) -> some View {
    HStack(spacing: UISpacing.small) {
      Text("已选 \(selected) / \(total)")
        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
      Spacer()
      Button("全选", action: selectAll)
      Button("清空", action: clear)
    }
    .buttonStyle(.borderless)
  }

  private var twoColumnGrid: [GridItem] {
    [
      GridItem(.flexible(minimum: 190), spacing: UISpacing.small),
      GridItem(.flexible(minimum: 190), spacing: UISpacing.small),
    ]
  }

  private struct OwnerChoice: Identifiable {
    var id: String
    var login: String
    var title: String
    var subtitle: String
    var isOrganization: Bool
    var accountIDs: Set<String>
    var latestUpdate: Date?
  }
}

private struct LinearIntegrationDetail: View {
  @Bindable var model: AppModel
  @State private var workspace: String
  @State private var teamKeys: String

  init(model: AppModel) {
    self.model = model
    _workspace = State(initialValue: model.settings.linearWorkspace)
    _teamKeys = State(initialValue: model.settings.linearTeamKeys.joined(separator: ", "))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: UISpacing.xLarge) {
        IntegrationHeader(
          icon: .application(name: "Linear"),
          title: "Linear",
          status: configured ? "已配置，复制对应 team 的 issue ID 即可触发。" : "填写 workspace 与 team key 后启用。",
          isHealthy: configured,
          actionTitle: "保存配置",
          action: save
        )
        Divider()
        UISectionHeading(title: "链接配置", subtitle: "这些字段只用于识别 issue ID 和构造 Linear 网页链接。")
        Grid(alignment: .leading, horizontalSpacing: UISpacing.medium, verticalSpacing: UISpacing.medium) {
          GridRow {
            UIControlLabel(text: "Workspace")
            TextField("例如 acme", text: $workspace).textFieldStyle(.roundedBorder)
          }
          GridRow {
            UIControlLabel(text: "Team keys")
            TextField("例如 ENG, APP", text: $teamKeys).textFieldStyle(.roundedBorder)
          }
        }
        IntegrationNotice(
          symbol: "lock.shield",
          color: .green,
          title: "不需要 API Key",
          detail: "DevLauncher 只打开 Linear 网页，不读取 issue 内容，也不会把剪贴板内容发送到网络。"
        )
        HStack {
          Button("保存", action: save).buttonStyle(.borderedProminent).disabled(!canSave)
          Button("测试当前配置", systemImage: "play.fill") {
            let key = parsedKeys.first ?? "ENG"
            model.showPanel(for: "\(key)-42")
          }
          .disabled(!configured)
        }
      }
      .padding(28).frame(maxWidth: 880, alignment: .leading)
    }
  }

  private var parsedKeys: [String] {
    teamKeys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }
  private var canSave: Bool { !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !parsedKeys.isEmpty }
  private var configured: Bool { !model.settings.linearWorkspace.isEmpty && !model.settings.linearTeamKeys.isEmpty }
  private func save() { model.updateLinear(workspace: workspace, teamKeys: parsedKeys) }
}

private struct ApplicationsIntegrationDetail: View {
  @Bindable var model: AppModel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: UISpacing.xLarge) {
        IntegrationHeader(
          icon: .system(symbolName: "square.grid.2x2"), title: "应用",
          status: "检查动作模板依赖的本机应用是否已安装。",
          isHealthy: model.installedApplications.contains(where: \.installed),
          actionTitle: "重新检测", action: { model.refreshIntegrations() })
        Divider()
        VStack(spacing: 0) {
          ForEach(model.installedApplications, id: \.name) { item in
            HStack(spacing: UISpacing.medium) {
              UIActionIcon(icon: .application(name: item.name), pointSize: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.callout.weight(.semibold))
                Text(item.installed ? "动作可以直接使用" : "未安装，相关候选会明确置灰")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              StatusBadge(healthy: item.installed, healthyText: "可用", unhealthyText: "未安装")
            }
            .padding(.horizontal, UISpacing.medium).frame(height: 58)
            Divider()
          }
        }
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
      }
      .padding(28).frame(maxWidth: 880, alignment: .leading)
    }
  }
}

private struct ScriptIntegrationDetail: View {
  @Bindable var model: AppModel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: UISpacing.xLarge) {
        IntegrationHeader(
          icon: .application(name: "Terminal"), title: "脚本环境",
          status: "脚本动作会根据 shebang 或扩展名选择解释器。",
          isHealthy: model.scriptEnvironments.contains(where: \.available),
          actionTitle: "重新检测", action: { model.refreshIntegrations() })
        Divider()
        ForEach(model.scriptEnvironments, id: \.name) { item in
          HStack(spacing: UISpacing.medium) {
            Image(systemName: item.available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .font(.title2).foregroundStyle(item.available ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
              Text(item.name).font(.headline)
              Text(item.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(healthy: item.available, healthyText: "可用", unhealthyText: "缺失")
          }
          .padding(UISpacing.large)
          .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        }
        IntegrationNotice(
          symbol: "info.circle", color: .blue, title: "缺失时不会静默失败",
          detail: "解释器或脚本不存在时，浮层会直接说明缺少什么，动作不会执行。")
      }
      .padding(28).frame(maxWidth: 880, alignment: .leading)
    }
  }
}

private struct IntegrationHeader: View {
  let icon: CandidateIcon
  let title: String
  let status: String
  let isHealthy: Bool
  let actionTitle: String
  let action: () -> Void
  var body: some View {
    HStack(spacing: UISpacing.large) {
      UIActionIcon(icon: icon, pointSize: 30, style: .tintedTile)
        .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: UISpacing.xSmall) {
        Text(title).font(.title2.weight(.bold))
        Label(status, systemImage: "circle.fill")
          .font(.callout).foregroundStyle(isHealthy ? .green : .orange)
      }
      Spacer()
      Button(actionTitle, action: action).buttonStyle(.bordered)
    }
  }
}

private struct IntegrationNotice: View {
  let symbol: String
  let color: Color
  let title: String
  let detail: String
  var body: some View {
    HStack(alignment: .top, spacing: UISpacing.medium) {
      Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.callout.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(UISpacing.medium).frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct StatusBadge: View {
  let healthy: Bool
  let healthyText: String
  let unhealthyText: String
  var body: some View {
    Text(healthy ? healthyText : unhealthyText)
      .font(.caption.weight(.semibold)).foregroundStyle(healthy ? .green : .orange)
      .padding(.horizontal, 9).frame(height: 24)
      .background((healthy ? Color.green : Color.orange).opacity(0.1), in: Capsule())
  }
}
