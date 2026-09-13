import DevLauncherCore
import SwiftUI

struct ActivityView: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      retentionHint
      Divider()
      if model.activity.entries.isEmpty {
        emptyState
      } else {
        activityList
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: UISpacing.large) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(.black, in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: UISpacing.xSmall) {
        Text("活动").font(.title2.weight(.bold))
        Text("只记录时间、规则、动作和结果，不保存剪贴板内容或完整参数。")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Picker(
        "最多保留",
        selection: Binding(
          get: { model.settings.activityRetentionLimit },
          set: { model.updateActivityRetentionLimit($0) }
        )
      ) {
        ForEach(ActivityLedger.supportedRetentionLimits, id: \.self) { limit in
          Text("\(limit.formatted()) 条").tag(limit)
        }
      }
      .pickerStyle(.menu)
      .fixedSize()
      .accessibilityLabel("活动最多保留条数")
      Button("清空活动", systemImage: "trash", role: .destructive) { model.clearActivity() }
        .disabled(model.activity.entries.isEmpty)
    }
    .padding(28)
  }

  private var retentionHint: some View {
    HStack(spacing: UISpacing.small) {
      Image(systemName: "info.circle")
      Text("调低上限会立即删除较早的记录，只保留最新 \(model.settings.activityRetentionLimit.formatted()) 条。")
      Spacer()
      Text("当前 \(model.activity.entries.count.formatted()) 条 · 上限 \(model.settings.activityRetentionLimit.formatted()) 条")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 28)
    .frame(minHeight: 36)
  }

  private var emptyState: some View {
    VStack(spacing: UISpacing.medium) {
      Image(systemName: "clock.badge.checkmark")
        .font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
      Text("还没有活动").font(.title3.weight(.semibold))
      Text("从浮层执行动作后，结果会安全地显示在这里。")
        .font(.callout).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var activityList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(model.activity.entries.reversed()) { entry in
          HStack(spacing: UISpacing.medium) {
            Image(systemName: entry.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
              .font(.system(size: 18)).foregroundStyle(entry.status == .succeeded ? .green : .red)
              .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
              Text(entry.actionTitle).font(.callout.weight(.semibold))
              Text(entry.ruleName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.status == .succeeded ? "成功" : "失败")
              .font(.caption.weight(.semibold))
              .foregroundStyle(entry.status == .succeeded ? .green : .red)
            Text(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .trailing)
          }
          .padding(.horizontal, 28).frame(height: 58)
          Divider().padding(.leading, 72)
        }
      }
      .padding(.vertical, UISpacing.small)
    }
  }
}
