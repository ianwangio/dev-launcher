import DevLauncherCore
import SwiftUI

struct ActionPickerView: View {
  @Environment(\.dismiss) private var dismiss
  let onAdd: (Action) -> Void
  @State private var selection: Selection = .kind(.openURL)
  @State private var draftAction = ActionCatalog.defaultAction(for: .openURL)
  @State private var showsConfiguration = false

  var body: some View {
    HSplitView {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(ActionCategory.allCases) { category in
            catalogSection(category.title) {
              ForEach(ActionCatalog.descriptors(in: category)) { descriptor in
                catalogRow(
                  id: .kind(descriptor.kind),
                  title: descriptor.title,
                  summary: descriptor.summary,
                  icon: .system(symbolName: descriptor.symbolName),
                  badge: "类型"
                )
              }
              ForEach(ActionCatalog.templates(in: category)) { template in
                catalogRow(
                  id: .template(template.id),
                  title: template.title,
                  summary: template.summary,
                  icon: ActionCatalog.icon(for: template.action),
                  badge: "模板"
                )
              }
            }
          }
        }
        .padding(16)
      }
      .frame(minWidth: 320, idealWidth: 350)
      .background(Color(nsColor: .controlBackgroundColor))

      VStack(alignment: .leading, spacing: 18) {
        let action = selectedAction
        let preview = ActionCatalog.preview(action, values: ["匹配内容": "next.js"])

        HStack(spacing: 12) {
          UIActionIcon(icon: ActionCatalog.icon(for: action), pointSize: 26, style: .tintedTile)
            .frame(width: 44, height: 44)
          VStack(alignment: .leading) {
            Text(action.title)
              .font(.title3.weight(.semibold))
            Text("添加后可以继续修改标题、目标和高级参数。")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        ActionConfigurationSummary(action: action)
        Button("配置参数", systemImage: "slider.horizontal.3") {
          showsConfiguration = true
        }
        .buttonStyle(.bordered)

        GroupBox("预览") {
          HStack(spacing: 10) {
            UIActionIcon(icon: ActionCatalog.icon(for: action), pointSize: 18)
            VStack(alignment: .leading, spacing: 2) {
              Text(preview.title).fontWeight(.medium)
              Text(preview.context).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "return")
              .foregroundStyle(.tertiary)
          }
          .padding(6)
        }

        Spacer()

        HStack {
          Spacer()
          Button("取消") { dismiss() }
          Button("添加动作") {
            onAdd(action)
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .disabled(!ActionCatalog.validate(action).isValid)
        }
      }
      .padding(22)
      .frame(minWidth: 470)
    }
    .frame(width: 850, height: 620)
    .sheet(isPresented: $showsConfiguration) {
      ActionConfigurationView(action: draftAction) { draftAction = $0 }
    }
  }

  private var selectedAction: Action {
    draftAction
  }

  private func action(for selection: Selection) -> Action {
    switch selection {
    case .kind(let kind): ActionCatalog.defaultAction(for: kind)
    case .template(let id):
      ActionCatalog.templates.first { $0.id == id }?.action
        ?? ActionCatalog.defaultAction(for: .openURL)
    }
  }

  private func catalogSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      content()
    }
  }

  private func catalogRow(
    id: Selection,
    title: String,
    summary: String,
    icon: CandidateIcon,
    badge: String
  ) -> some View {
    Button {
      selection = id
      draftAction = action(for: id)
    } label: {
      HStack(spacing: 10) {
        UIActionIcon(icon: icon, pointSize: 18)
          .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.callout.weight(.medium))
          Text(summary).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text(badge)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(7)
      .background(
        selection == id ? Color.accentColor.opacity(0.14) : Color.clear,
        in: RoundedRectangle(cornerRadius: 7)
      )
    }
    .buttonStyle(.plain)
  }

  private enum Selection: Hashable {
    case kind(ActionKind)
    case template(String)
  }
}

private struct ActionConfigurationSummary: View {
  let action: Action

  var body: some View {
    Form {
      LabeledContent("浮层标题", value: action.title)
      LabeledContent("目标", value: target)
      DisclosureGroup("高级参数") {
        Text("完整模板与参数会在添加后显示。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var target: String {
    switch action {
    case .openURL: "链接模板"
    case .openPath: "匹配内容"
    case .openWithApplication(let value):
      value.applicationName.isEmpty ? "选择应用" : value.applicationName
    case .runScript(let value): value.scriptPath.isEmpty ? "选择脚本" : value.scriptPath
    case .copyText: "文本模板"
    case .repoPicker: "GitHub 仓库"
    }
  }
}

struct ActionConfigurationView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: Action
  let onSave: (Action) -> Void

  init(action: Action, onSave: @escaping (Action) -> Void) {
    _draft = State(initialValue: action)
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("配置动作")
        .font(.title2.weight(.bold))
      actionFields
      Spacer()
      HStack {
        Spacer()
        Button("取消") { dismiss() }
        Button("保存") {
          onSave(draft)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!ActionCatalog.validate(draft).isValid)
      }
    }
    .padding(22)
    .frame(width: 560, height: 420)
  }

  @ViewBuilder
  private var actionFields: some View {
    switch draft {
    case .openURL(let action):
      fields(
        title: binding(action.title) {
          .openURL(OpenURLAction(title: $0, urlTemplate: action.urlTemplate))
        },
        targetLabel: "链接模板",
        target: binding(action.urlTemplate) {
          .openURL(OpenURLAction(title: action.title, urlTemplate: $0))
        }
      )
    case .openPath(let action):
      fields(
        title: binding(action.title) {
          .openPath(OpenPathAction(title: $0, pathTemplate: action.pathTemplate))
        },
        targetLabel: "路径模板",
        target: binding(action.pathTemplate) {
          .openPath(OpenPathAction(title: action.title, pathTemplate: $0))
        }
      )
    case .openWithApplication(let action):
      TextField(
        "浮层标题",
        text: binding(action.title) {
          .openWithApplication(
            OpenWithApplicationAction(
              title: $0,
              applicationName: action.applicationName,
              targetTemplate: action.targetTemplate
            )
          )
        }
      )
      TextField(
        "应用名称",
        text: binding(action.applicationName) {
          .openWithApplication(
            OpenWithApplicationAction(
              title: action.title,
              applicationName: $0,
              targetTemplate: action.targetTemplate
            )
          )
        }
      )
      TextField(
        "打开目标",
        text: binding(action.targetTemplate) {
          .openWithApplication(
            OpenWithApplicationAction(
              title: action.title,
              applicationName: action.applicationName,
              targetTemplate: $0
            )
          )
        }
      )
    case .runScript(let action):
      fields(
        title: binding(action.title) {
          .runScript(RunScriptAction(title: $0, scriptPath: action.scriptPath, args: action.args))
        },
        targetLabel: "脚本路径",
        target: binding(action.scriptPath) {
          .runScript(RunScriptAction(title: action.title, scriptPath: $0, args: action.args))
        }
      )
    case .copyText(let action):
      fields(
        title: binding(action.title) {
          .copyText(CopyTextAction(title: $0, textTemplate: action.textTemplate))
        },
        targetLabel: "文本模板",
        target: binding(action.textTemplate) {
          .copyText(CopyTextAction(title: action.title, textTemplate: $0))
        }
      )
    case .repoPicker(let action):
      fields(
        title: binding(action.title) {
          .repoPicker(RepoPickerAction(title: $0, issueURLTemplate: action.issueURLTemplate))
        },
        targetLabel: "链接模板",
        target: binding(action.issueURLTemplate) {
          .repoPicker(RepoPickerAction(title: action.title, issueURLTemplate: $0))
        }
      )
    }

    HStack(spacing: 6) {
      Text("可插入：")
      Text("匹配内容")
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
      Text("命名值")
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func fields(title: Binding<String>, targetLabel: String, target: Binding<String>)
    -> some View
  {
    Form {
      TextField("浮层标题", text: title)
      TextField(targetLabel, text: target)
      DisclosureGroup("高级参数") {
        Text("技术模板仅在这里显示，不会进入日常浮层。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func binding(_ value: String, update: @escaping (String) -> Action) -> Binding<String> {
    Binding {
      value
    } set: {
      draft = update($0)
    }
  }
}
