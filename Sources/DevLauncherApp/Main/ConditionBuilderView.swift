import DevLauncherCore
import SwiftUI

struct ConditionBuilderView: View {
  @Binding var expression: ConditionExpression
  let issues: [ConditionIssue]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if case .predicate = expression {
        Button("转换为条件组", systemImage: "arrow.triangle.branch") {
          expression = .group(ConditionGroup(combinator: .all, children: [expression]))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      ConditionNodeView(
        expression: $expression, issues: issues, depth: 1, canRemove: false, onRemove: {})
    }
  }
}

private struct ConditionNodeView: View {
  @Binding var expression: ConditionExpression
  let issues: [ConditionIssue]
  let depth: Int
  let canRemove: Bool
  let onRemove: () -> Void

  var body: some View {
    switch expression {
    case .group:
      groupEditor
    case .predicate:
      predicateEditor
    }
  }

  private var groupEditor: some View {
    let group = groupValue
    return VStack(alignment: .leading, spacing: UISpacing.medium) {
      HStack(spacing: UISpacing.small) {
        UIControlLabel(text: "组合方式")

        Picker("组合方式", selection: combinatorBinding) {
          ForEach(ConditionCombinator.allCases, id: \.self) { item in
            Text(item.title).tag(item)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: UISize.fieldColumn + UISpacing.small + UISize.operationColumn)
        .frame(height: UISize.formControlHeight)

        Spacer()
        if canRemove {
          UIIconButton(symbol: "trash", label: "删除条件组", action: onRemove)
        }
      }

      VStack(spacing: UISpacing.small) {
        ForEach(Array(group.children.indices), id: \.self) { index in
          AnyView(
            ConditionNodeView(
              expression: childBinding(at: index),
              issues: issues,
              depth: depth + 1,
              canRemove: true,
              onRemove: { removeChild(at: index) }
            )
          )
        }
      }
      .padding(.leading, depth > 1 ? UISpacing.large : 0)

      HStack {
        Button("添加条件", systemImage: "plus") { addPredicate() }
          .disabled(group.children.count >= ConditionEngine.maximumChildrenPerGroup)
        Button("添加条件组", systemImage: "folder.badge.plus") { addGroup() }
          .disabled(
            depth >= ConditionEngine.maximumDepth
              || group.children.count >= ConditionEngine.maximumChildrenPerGroup
          )
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(depth > 1 ? UISpacing.medium : 0)
    .background(
      depth > 1 ? Color.accentColor.opacity(0.055) : Color.clear,
      in: RoundedRectangle(cornerRadius: 9)
    )
    .overlay(alignment: .leading) {
      if depth > 1 {
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.accentColor.opacity(0.45))
          .frame(width: 3)
          .padding(.vertical, 8)
      }
    }
  }

  private var predicateEditor: some View {
    let predicate = predicateValue
    let nodeIssues = issues.filter { $0.nodeID == predicate.id }

    return VStack(alignment: .leading, spacing: UISpacing.xSmall) {
      HStack(spacing: UISpacing.small) {
        Picker("字段", selection: fieldBinding) {
          ForEach(ConditionField.allCases, id: \.self) { field in
            Text(field.title).tag(field)
          }
        }
        .labelsHidden()
        .frame(width: UISize.fieldColumn)
        .frame(height: UISize.formControlHeight)

        Picker("比较方式", selection: operationBinding) {
          ForEach(operations(for: predicate.field), id: \.self) { operation in
            Text(operation.title).tag(operation)
          }
        }
        .labelsHidden()
        .frame(width: UISize.operationColumn)
        .frame(height: UISize.formControlHeight)

        if predicate.operation != .isTrue {
          TextField("匹配值", text: valueBinding)
            .textFieldStyle(.roundedBorder)
            .frame(height: UISize.formControlHeight)
        } else {
          Text("为真")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: UISize.formControlHeight)
        }

        UIIconButton(symbol: "minus.circle", label: "删除条件", action: onRemove)
      }

      HStack(spacing: UISpacing.medium) {
        UICheckbox(title: "忽略大小写", isOn: caseInsensitiveBinding)
          .disabled(predicate.operation == .isTrue)
        Text("命名值")
          .font(.caption)
          .foregroundStyle(.secondary)
        TextField("命名值（可选）", text: captureNameBinding)
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
          .frame(minWidth: 90, idealWidth: 170, maxWidth: 210)
          .frame(height: UISize.auxiliaryRowHeight)
        Spacer()
      }
      .foregroundStyle(.secondary)

      ForEach(nodeIssues, id: \.message) { issue in
        Label(issue.message, systemImage: "exclamationmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.red)
      }

      if let advisory = ConditionEngine.advisory(for: predicate) {
        Label(advisory, systemImage: "info.circle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(UISpacing.medium)
    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }

  private var groupValue: ConditionGroup {
    if case .group(let group) = expression { return group }
    return ConditionGroup(combinator: .all, children: [])
  }

  private var predicateValue: ConditionPredicate {
    if case .predicate(let predicate) = expression { return predicate }
    return ConditionPredicate(field: .text, operation: .contains, value: "")
  }

  private var combinatorBinding: Binding<ConditionCombinator> {
    Binding {
      groupValue.combinator
    } set: { value in
      var group = groupValue
      group.combinator = value
      expression = .group(group)
    }
  }

  private func childBinding(at index: Int) -> Binding<ConditionExpression> {
    Binding {
      let children = groupValue.children
      guard children.indices.contains(index) else {
        return .predicate(ConditionPredicate(field: .text, operation: .contains, value: ""))
      }
      return children[index]
    } set: { value in
      var group = groupValue
      guard group.children.indices.contains(index) else { return }
      group.children[index] = value
      expression = .group(group)
    }
  }

  private func removeChild(at index: Int) {
    var group = groupValue
    guard group.children.indices.contains(index) else { return }
    group.children.remove(at: index)
    expression = .group(group)
  }

  private func addPredicate() {
    var group = groupValue
    guard group.children.count < ConditionEngine.maximumChildrenPerGroup else { return }
    group.children.append(
      .predicate(ConditionPredicate(field: .text, operation: .contains, value: "匹配内容"))
    )
    expression = .group(group)
  }

  private func addGroup() {
    var group = groupValue
    guard depth < ConditionEngine.maximumDepth,
      group.children.count < ConditionEngine.maximumChildrenPerGroup
    else { return }
    group.children.append(
      .group(
        ConditionGroup(
          combinator: .any,
          children: [
            .predicate(ConditionPredicate(field: .text, operation: .contains, value: "匹配内容"))
          ]
        )
      )
    )
    expression = .group(group)
  }

  private var fieldBinding: Binding<ConditionField> {
    predicateBinding(\.field) { predicate, field in
      predicate.field = field
      predicate.operation = field.defaultOperation
      if field == .fileExists { predicate.value = "true" }
    }
  }

  private var operationBinding: Binding<ConditionOperation> {
    predicateBinding(\.operation) { predicate, operation in
      predicate.operation = operation
    }
  }

  private var valueBinding: Binding<String> {
    predicateBinding(\.value) { predicate, value in
      predicate.value = value
    }
  }

  private var caseInsensitiveBinding: Binding<Bool> {
    predicateBinding(\.caseInsensitive) { predicate, value in
      predicate.caseInsensitive = value
    }
  }

  private var captureNameBinding: Binding<String> {
    Binding {
      predicateValue.captureName ?? ""
    } set: { value in
      var predicate = predicateValue
      predicate.captureName = value.isEmpty ? nil : value
      expression = .predicate(predicate)
    }
  }

  private func predicateBinding<Value>(
    _ keyPath: KeyPath<ConditionPredicate, Value>,
    set: @escaping (inout ConditionPredicate, Value) -> Void
  ) -> Binding<Value> {
    Binding {
      predicateValue[keyPath: keyPath]
    } set: { value in
      var predicate = predicateValue
      set(&predicate, value)
      expression = .predicate(predicate)
    }
  }

  private func operations(for field: ConditionField) -> [ConditionOperation] {
    switch field {
    case .fileExists: [.isTrue]
    case .text: [.equals, .contains, .beginsWith, .endsWith, .matchesRegularExpression]
    default: [.equals, .contains, .beginsWith, .endsWith]
    }
  }
}
