import DevLauncherCore
import SwiftUI

struct RuleEditorView: View {
  @State private var draft: Rule
  @State private var sample = "https://github.com/openai/codex/issues/42"
  @State private var validation: RuleValidation
  @State private var saveMessage: String?
  @State private var showsActionPicker = false
  @State private var editingActionIndex: Int?

  let onSave: (Rule) -> RuleValidation
  let readClipboard: () -> String
  let writeClipboard: (String) -> Void

  init(
    rule: Rule,
    onSave: @escaping (Rule) -> RuleValidation,
    readClipboard: @escaping () -> String,
    writeClipboard: @escaping (String) -> Void
  ) {
    _draft = State(initialValue: rule)
    _validation = State(
      initialValue: RuleCatalog(ruleSet: RuleSet(rules: [rule])).validate(rule)
    )
    self.onSave = onSave
    self.readClipboard = readClipboard
    self.writeClipboard = writeClipboard
  }

  private var evaluation: MatchEvaluation {
    ConditionEngine.evaluate(
      draft.condition,
      against: NormalizedClipboard(text: sample, kind: inferredKind(sample))
    )
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        Divider()
        editor
      }
      .padding(.horizontal, 26)
      .padding(.vertical, 22)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: draft) { _, _ in revalidate() }
    .sheet(isPresented: $showsActionPicker) {
      ActionPickerView { action in
        draft.actions.append(action)
      }
    }
    .sheet(
      isPresented: Binding(
        get: { editingActionIndex != nil },
        set: { if !$0 { editingActionIndex = nil } }
      )
    ) {
      if let index = editingActionIndex, draft.actions.indices.contains(index) {
        ActionConfigurationView(action: draft.actions[index]) { action in
          draft.actions[index] = action
        }
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      RuleIconView(kind: RulePresentation.project(draft).icon)
        .frame(width: 52, height: 52)

      VStack(alignment: .leading, spacing: 6) {
        TextField("规则名称", text: $draft.name)
          .font(.title2.weight(.bold))
          .textFieldStyle(.plain)
        Text("自定义规则 · 可以编辑条件和动作")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer()

      UIEnableToggle(
        "启用",
        accessibilityLabel: "启用\(draft.name)",
        isOn: $draft.enabled
      )

      Button("保存") {
        validation = onSave(draft)
        saveMessage = validation.isValid ? "已保存" : "请修正标出的配置"
      }
      .buttonStyle(.borderedProminent)
      .disabled(!validation.isValid)
    }
    .padding(.bottom, 18)
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 24) {
      editorSection("匹配条件", subtitle: "组合多个条件，并用 AND 或 OR 控制规则何时触发。") {
        ConditionBuilderView(expression: $draft.condition, issues: validation.conditionIssues)
      }

      editorSection("动作", subtitle: "匹配后，浮层会按顺序显示这些动作。") {
        VStack(spacing: 0) {
          ForEach(Array(draft.actions.indices), id: \.self) { index in
            let action = draft.actions[index]
            let preview = ActionCatalog.preview(
              action,
              values: ["匹配内容": sample.isEmpty ? "匹配内容" : sample]
            )
            HStack(spacing: 10) {
              Image(systemName: preview.symbolName)
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(preview.title).fontWeight(.medium)
                Text(preview.context)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()

              if let message = validation.actionMessages[index] {
                Text(message)
                  .font(.caption)
                  .foregroundStyle(.red)
              }

              UIOverflowMenu {
                Button("配置") { editingActionIndex = index }
                Button("上移") { moveAction(index, offset: -1) }
                  .disabled(index == draft.actions.startIndex)
                Button("下移") { moveAction(index, offset: 1) }
                  .disabled(index == draft.actions.index(before: draft.actions.endIndex))
                Divider()
                Button("删除", role: .destructive) { draft.actions.remove(at: index) }
              }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if index < draft.actions.index(before: draft.actions.endIndex) {
              Divider().padding(.leading, 48)
            }
          }
        }
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))

        Button("添加动作", systemImage: "plus") {
          showsActionPicker = true
        }
        .buttonStyle(.bordered)
      }

      editorSection("测试规则", subtitle: "输入内容，查看每个条件和最终候选。") {
        HStack {
          TextField("输入测试内容", text: $sample)
            .textFieldStyle(.roundedBorder)
          Button("粘贴", systemImage: "doc.on.clipboard") {
            sample = readClipboard()
          }
          .controlSize(.small)
          Button("复制", systemImage: "doc.on.doc") {
            writeClipboard(sample)
          }
          .controlSize(.small)
          .disabled(sample.isEmpty)
          Label(
            evaluation.matches ? "匹配成功" : "没有匹配",
            systemImage: evaluation.matches ? "checkmark.circle.fill" : "xmark.circle"
          )
          .font(.callout.weight(.medium))
          .foregroundStyle(evaluation.matches ? Color.green : Color.secondary)
        }

        if evaluation.matches {
          VStack(spacing: 0) {
            ForEach(Array(draft.actions.indices), id: \.self) { index in
              let preview = ActionCatalog.preview(
                draft.actions[index],
                values: ["匹配内容": sample]
              )
              HStack(spacing: 10) {
                Image(systemName: preview.symbolName)
                Text(preview.title).fontWeight(.medium)
                Text("· \(preview.context)")
                  .foregroundStyle(.secondary)
                Spacer()
              }
              .padding(9)
              if index < draft.actions.index(before: draft.actions.endIndex) { Divider() }
            }
          }
          .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        }

        if let saveMessage {
          Text(saveMessage)
            .font(.caption)
            .foregroundStyle(validation.isValid ? .green : .red)
        }
      }
    }
    .padding(.top, 20)
  }

  private func editorSection<Content: View>(
    _ title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      Text(subtitle).font(.callout).foregroundStyle(.secondary)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func revalidate() {
    validation = RuleCatalog(ruleSet: RuleSet(rules: [draft])).validate(draft)
    saveMessage = nil
  }

  private func moveAction(_ index: Int, offset: Int) {
    let destination = index + offset
    guard draft.actions.indices.contains(index), draft.actions.indices.contains(destination) else {
      return
    }
    draft.actions.swapAt(index, destination)
  }

  private func inferredKind(_ text: String) -> ClipboardContentKind {
    if URLComponents(string: text)?.scheme != nil { return .url }
    if text.hasPrefix("/") || text.hasPrefix("~/") { return .file }
    return .plainText
  }
}
