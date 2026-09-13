import AppKit
import DevLauncherCore
import SwiftUI

struct RuleWorkbenchView: View {
  @Bindable var model: AppModel
  @State private var selectedRuleID: String?
  @State private var searchText = ""

  private var catalog: RuleLibraryPresentation {
    RuleLibraryPresentation(ruleSet: model.ruleSet, searchText: searchText)
  }

  private var selectedRule: RulePresentation? {
    let fallback = catalog.builtin.first ?? catalog.custom.first
    guard let selectedRuleID else { return fallback }
    return (catalog.builtin + catalog.custom).first { $0.id == selectedRuleID } ?? fallback
  }

  var body: some View {
    HSplitView {
      ruleList
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
      ruleDetail
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      if selectedRuleID == nil {
        selectedRuleID = catalog.builtin.first?.id ?? catalog.custom.first?.id
      }
    }
  }

  private var ruleList: some View {
    VStack(spacing: 0) {
      HStack {
        Text("规则")
          .font(.title2.weight(.bold))
        Spacer()
        Button {
          if let id = model.createCustomRule() { selectedRuleID = id }
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 15, weight: .medium))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .help("新建自定义规则")
      }
      .padding(.horizontal, 16)
      .padding(.top, 15)
      .padding(.bottom, 11)

      HStack(spacing: 7) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("搜索规则…", text: $searchText)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal, 10)
      .frame(height: 32)
      .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
      .padding(.horizontal, 12)
      .padding(.bottom, 10)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          RuleSection(
            title: "内置规则",
            items: catalog.builtin,
            selectedRuleID: $selectedRuleID,
            onToggle: { id, enabled in model.setRuleEnabled(id, enabled: enabled) },
            onDuplicate: { id in
              if let newID = model.duplicateRule(id) { selectedRuleID = newID }
            },
            onDelete: { _ in }
          )

          RuleSection(
            title: "自定义规则",
            items: catalog.custom,
            selectedRuleID: $selectedRuleID,
            showsCustomMenu: true,
            onToggle: { id, enabled in model.setRuleEnabled(id, enabled: enabled) },
            onDuplicate: { id in
              if let newID = model.duplicateRule(id) { selectedRuleID = newID }
            },
            onDelete: { id in
              model.deleteCustomRule(id)
              selectedRuleID = catalog.builtin.first?.id
            }
          )

          if catalog.custom.isEmpty {
            VStack(spacing: 5) {
              Text("还没有自定义规则")
                .font(.callout.weight(.medium))
              Text("点右上角的加号创建第一条规则。")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
          }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  @ViewBuilder
  private var ruleDetail: some View {
    if let selectedRule {
      if selectedRule.origin == .custom,
        let source = model.ruleSet.rules.first(where: { $0.id == selectedRule.id })
      {
        RuleEditorView(
          rule: source,
          onSave: model.saveRule,
          readClipboard: model.clipboardTextForTesting,
          writeClipboard: model.copyTestText
        )
        .id(source.id)
      } else {
        RuleDetailPreview(
          rule: selectedRule,
          model: model,
          onToggle: { enabled in model.setRuleEnabled(selectedRule.id, enabled: enabled) },
          onDuplicate: {
            if let id = model.duplicateRule(selectedRule.id) { selectedRuleID = id }
          },
          onAddAction: { model.appendAction($0, to: selectedRule.id) },
          onRemoveAction: { model.removeAction(at: $0, from: selectedRule.id) },
          onRestoreActions: { model.restoreBuiltinActions(selectedRule.id) }
        )
        .id(selectedRule.id)
      }
    } else {
      ContentUnavailableView("没有规则", systemImage: "doc.text.magnifyingglass")
    }
  }
}

private struct RuleSection: View {
  let title: String
  let items: [RulePresentation]
  @Binding var selectedRuleID: String?
  var showsCustomMenu = false
  let onToggle: (String, Bool) -> Void
  let onDuplicate: (String) -> Void
  let onDelete: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
        Spacer()
        Text("\(items.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 7)
      .padding(.top, 8)

      ForEach(items) { item in
        RuleRow(
          rule: item,
          isSelected: selectedRuleID == item.id,
          showsCustomMenu: showsCustomMenu,
          onToggle: { onToggle(item.id, $0) },
          onDuplicate: { onDuplicate(item.id) },
          onDelete: { onDelete(item.id) }
        ) {
          selectedRuleID = item.id
        }
      }
    }
  }
}

private struct RuleRow: View {
  let rule: RulePresentation
  let isSelected: Bool
  let showsCustomMenu: Bool
  let onToggle: (Bool) -> Void
  let onDuplicate: () -> Void
  let onDelete: () -> Void
  let select: () -> Void

  var body: some View {
    HStack(spacing: UISpacing.small) {
      UIEnableToggle(
        accessibilityLabel: "启用\(rule.name)",
        isOn: Binding(get: { rule.isEnabled }, set: { value in onToggle(value) })
      )

      Button(action: select) {
        HStack(spacing: 10) {
          RuleIconView(kind: rule.icon)
            .frame(width: UISize.ruleIcon, height: UISize.ruleIcon)

          VStack(alignment: .leading, spacing: 3) {
            Text(rule.name)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            Text(rule.subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if showsCustomMenu {
        UIOverflowMenu {
          Button("复制", action: onDuplicate)
          Button("删除", role: .destructive, action: onDelete)
        }
      }
    }
    .padding(.horizontal, 8)
    .frame(minHeight: UISize.ruleRow)
    .background(
      isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .accessibilityLabel("\(rule.name)，\(rule.origin == .builtin ? "内置规则" : "自定义规则")")
  }
}

private struct RuleDetailPreview: View {
  let rule: RulePresentation
  @Bindable var model: AppModel
  let onToggle: (Bool) -> Void
  let onDuplicate: () -> Void
  let onAddAction: (Action) -> Void
  let onRemoveAction: (Int) -> Void
  let onRestoreActions: () -> Void
  @State private var sample = ""
  @State private var showsActionPicker = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        Divider()
        content
      }
      .padding(.horizontal, 26)
      .padding(.vertical, 22)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .sheet(isPresented: $showsActionPicker) {
      ActionPickerView { action in onAddAction(action) }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      RuleIconView(kind: rule.icon)
        .frame(width: 52, height: 52)

      VStack(alignment: .leading, spacing: 4) {
        Text(rule.name)
          .font(.title2.weight(.bold))
        Text(rule.subtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer()

      UIEnableToggle(
        rule.isEnabled ? "启用" : "停用",
        accessibilityLabel: "启用\(rule.name)",
        isOn: Binding(get: { rule.isEnabled }, set: { value in onToggle(value) })
      )
    }
    .padding(.bottom, 18)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 22) {
      if rule.origin == .builtin {
        HStack {
          Label("内置匹配条件固定，动作可以新增或删除。", systemImage: "lock.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Button("恢复默认动作", action: onRestoreActions)
            .buttonStyle(.bordered)
          Button("复制为自定义规则", action: onDuplicate)
            .buttonStyle(.bordered)
        }
        .padding(11)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      }

      detailSection("匹配条件", subtitle: "剪贴板内容满足以下条件时显示候选动作。") {
        LabeledContent("当前表达式") {
          Text(rule.matchSummary)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
      }

      detailSection("动作", subtitle: "浮层只展示动作名称和简短上下文。") {
        VStack(spacing: 0) {
          ForEach(Array(rule.actionTitles.enumerated()), id: \.offset) { index, title in
            HStack(spacing: 11) {
              UIActionIcon(icon: rule.actionIcons[index], pointSize: 20)
                .frame(width: 32, height: 32)
              VStack(alignment: .leading, spacing: 2) {
                Text(title)
                  .font(.body.weight(.medium))
                Text(rule.shortContext)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              UIOverflowMenu {
                Button("删除动作", role: .destructive) { onRemoveAction(index) }
              }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if title != rule.actionTitles.last { Divider().padding(.leading, 47) }
          }
        }
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))

        Button("添加动作", systemImage: "plus") { showsActionPicker = true }
          .buttonStyle(.bordered)
      }

      detailSection("测试", subtitle: "输入内容，预览这条规则是否匹配。") {
        HStack {
          TextField("例如 /Users/chen/Devel 或 #1234", text: $sample)
            .textFieldStyle(.roundedBorder)
          Button("粘贴", systemImage: "doc.on.clipboard") {
            sample = model.clipboardTextForTesting()
          }
          .controlSize(.small)
          Button("复制", systemImage: "doc.on.doc") {
            model.copyTestText(sample)
          }
          .controlSize(.small)
          .disabled(sample.isEmpty)
          Button("测试") {
            model.showPanel(for: sample)
          }
          .buttonStyle(.borderedProminent)
          .disabled(sample.isEmpty)
        }

        if !sample.isEmpty {
          let matches = model.previewMatch(for: sample).filter { $0.ruleID == rule.id }
          Label(
            matches.isEmpty ? "这条规则没有匹配" : "匹配成功，将显示 \(matches.count) 个动作",
            systemImage: matches.isEmpty ? "xmark.circle" : "checkmark.circle.fill"
          )
          .font(.caption)
          .foregroundStyle(matches.isEmpty ? Color.secondary : Color.green)
        }
      }
    }
    .padding(.top, 20)
  }

  private func detailSection<Content: View>(
    _ title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      Text(subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension RuleIconKind {
  var systemName: String {
    switch self {
    case .localPath: "folder.fill"
    case .linear: "line.3.horizontal.decrease.circle.fill"
    case .github: "chevron.left.forwardslash.chevron.right"
    case .web: "safari"
    case .script: "terminal"
    case .copy: "doc.on.doc"
    case .application: "app"
    case .custom: "doc.text.fill"
    }
  }

  var tint: Color {
    switch self {
    case .localPath: .green
    case .linear: .indigo
    case .github: .primary
    case .web: .blue
    case .script: .secondary
    case .copy: .teal
    case .application: .accentColor
    case .custom: .blue
    }
  }
}

struct RuleIconView: View {
  let kind: RuleIconKind

  var body: some View {
    Group {
      if kind == .linear {
        UIActionIcon(icon: .application(name: "Linear"), pointSize: 22, style: .tintedTile)
      } else if kind == .github {
        UIActionIcon(icon: .application(name: "GitHub Desktop"), pointSize: 22, style: .tintedTile)
      } else if case .application(let name) = kind,
        let icon = ApplicationIconProvider.icon(named: name)
      {
        Image(nsImage: icon)
          .resizable()
          .scaledToFit()
          .padding(6)
      } else {
        Image(systemName: kind.systemName)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(kind.tint)
      }
    }
    .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityLabel(kind.accessibilityLabel)
  }
}

extension RuleIconKind {
  var accessibilityLabel: String {
    switch self {
    case .localPath: "文件规则"
    case .linear: "Linear 规则"
    case .github: "GitHub 规则"
    case .web: "网页规则"
    case .script: "脚本规则"
    case .copy: "复制规则"
    case .application(let name): "\(name) 应用规则"
    case .custom: "自定义规则"
    }
  }
}
