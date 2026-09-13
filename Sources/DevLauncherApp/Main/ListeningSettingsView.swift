import DevLauncherCore
import SwiftUI

struct ListeningSettingsView: View {
  @Bindable var model: AppModel
  @State private var draft: ListeningSettings

  init(model: AppModel) {
    self.model = model
    _draft = State(initialValue: model.settings.listening)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: UISpacing.xLarge) {
        header
        Divider()
        contentKinds
        Divider()
        behavior
        Divider()
        ignoredApplications
        Divider()
        pauseOptions
        Divider()
        startup
      }
      .padding(28)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: draft) { _, value in model.updateListeningSettings(value) }
    .onChange(of: model.settings.listening) { _, value in
      if value != draft { draft = value }
    }
  }

  private var header: some View {
    HStack(spacing: UISpacing.large) {
      Image(systemName: "waveform")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(.black, in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: UISpacing.xSmall) {
        HStack(spacing: UISpacing.small) {
          Text("监听").font(.title2.weight(.bold))
          Label(model.listeningStatusTitle, systemImage: "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(model.isListening ? .green : .orange)
        }
        Text("剪贴板内容只在内存中处理，不会被保存。")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      if model.isListening {
        Button("暂停", systemImage: "pause.fill") {
          model.pauseListening(seconds: 600)
          draft = model.settings.listening
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button("恢复监听", systemImage: "play.fill") {
          model.resumeListening()
          draft.pausedUntil = nil
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private var contentKinds: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "剪贴板内容", subtitle: "选择允许进入规则引擎的内容类型。")
      ForEach(ClipboardContentKind.allCases, id: \.self) { kind in
        HStack(spacing: UISpacing.medium) {
          Image(systemName: symbol(for: kind))
            .frame(width: 28)
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(kind.title).font(.callout.weight(.medium))
            Text(summary(for: kind)).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          UIEnableToggle(accessibilityLabel: "处理\(kind.title)", isOn: kindBinding(kind))
        }
        .frame(minHeight: 44)
      }
      HStack(spacing: UISpacing.medium) {
        Image(systemName: "photo").frame(width: 28).foregroundStyle(.tertiary)
        VStack(alignment: .leading, spacing: 2) {
          Text("图片").font(.callout.weight(.medium)).foregroundStyle(.secondary)
          Text("不读取或处理图片内容").font(.caption).foregroundStyle(.tertiary)
        }
        Spacer()
        Text("不处理").font(.caption).foregroundStyle(.secondary)
      }
      .frame(minHeight: 44)
    }
  }

  private var behavior: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "重复与长度", subtitle: "控制重复复制和内容长度限制。")
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("重复复制相同内容时仍然触发").font(.callout.weight(.medium))
          Text("每一次真实复制都会重新执行规则匹配。")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        UIEnableToggle(
          accessibilityLabel: "重复复制相同内容时仍然触发",
          isOn: $draft.repeatIdenticalCopies
        )
      }
      HStack(spacing: UISpacing.medium) {
        UIControlLabel(text: "最大内容长度")
        TextField("字符数", value: $draft.maximumContentLength, format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 150, height: UISize.formControlHeight)
        Text("字符").font(.caption).foregroundStyle(.secondary)
      }
      DisclosureGroup("高级选项") {
        HStack(spacing: UISpacing.medium) {
          UIControlLabel(text: "轮询间隔")
          TextField("毫秒", value: $draft.pollIntervalMilliseconds, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 150, height: UISize.formControlHeight)
          Text("毫秒").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, UISpacing.small)
      }
    }
  }

  private var ignoredApplications: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      HStack {
        UISectionHeading(
          title: "忽略的应用",
          subtitle: "应用位于前台时，已勾选的项目不会触发规则。"
        )
        Spacer()
        Button("选择应用…", systemImage: "plus") {
          addIgnoredApplications(model.selectIgnoredApplications())
        }
        .buttonStyle(.bordered)
      }

      if draft.ignoredApplications.isEmpty {
        ContentUnavailableView(
          "尚未添加应用",
          systemImage: "app.badge",
          description: Text("点击“选择应用…”从应用程序文件夹加入一个或多个应用。")
        )
        .frame(maxWidth: .infinity, minHeight: 130)
      } else {
        LazyVStack(spacing: UISpacing.xSmall) {
          ForEach($draft.ignoredApplications) { $ignoredApplication in
            let application = model.ignoredApplicationDescriptor(
              for: ignoredApplication.bundleIdentifier)
            HStack(spacing: UISpacing.medium) {
              Toggle("忽略 \(application.name)", isOn: $ignoredApplication.isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .accessibilityLabel("忽略 \(application.name)")
              Group {
                if let icon = ApplicationIconProvider.icon(
                  bundleIdentifier: application.bundleIdentifier)
                {
                  Image(nsImage: icon).resizable()
                } else {
                  Image(systemName: "app").resizable().scaledToFit().padding(5)
                }
              }
              .frame(width: 28, height: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(application.name).font(.callout.weight(.medium))
                Text(application.bundleIdentifier)
                  .font(.caption2.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer(minLength: UISpacing.small)
              UIIconButton(symbol: "trash", label: "从忽略列表删除 \(application.name)") {
                draft.ignoredApplications.removeAll {
                  $0.bundleIdentifier == application.bundleIdentifier
                }
              }
            }
            .padding(.horizontal, UISpacing.medium)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
          }
        }
      }
    }
  }

  private func addIgnoredApplications(_ applications: [InstalledApplicationDescriptor]) {
    for application in applications {
      if let index = draft.ignoredApplications.firstIndex(where: {
        $0.bundleIdentifier == application.bundleIdentifier
      }) {
        draft.ignoredApplications[index].isEnabled = true
      } else {
        draft.ignoredApplications.append(
          IgnoredApplication(bundleIdentifier: application.bundleIdentifier)
        )
      }
    }
    draft.ignoredApplications.sort {
      model.ignoredApplicationDescriptor(for: $0.bundleIdentifier).name
        .localizedCaseInsensitiveCompare(
          model.ignoredApplicationDescriptor(for: $1.bundleIdentifier).name
        ) == .orderedAscending
    }
  }

  private var pauseOptions: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "暂停选项", subtitle: "临时停止处理剪贴板内容。")
      HStack {
        Button("暂停 10 分钟") {
          model.pauseListening(seconds: 600)
          draft = model.settings.listening
        }
        Button("暂停 1 小时") {
          model.pauseListening(seconds: 3600)
          draft = model.settings.listening
        }
        Button("直到手动恢复") {
          model.pauseUntilResumed()
          draft = model.settings.listening
        }
        if !model.isListening {
          Button("立即恢复") {
            model.resumeListening()
            draft.pausedUntil = nil
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .buttonStyle(.bordered)
    }
  }

  private var startup: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "启动", subtitle: "控制登录启动与应用在 Dock 中的显示方式。")
      HStack {
        Text("开机时启动")
        Spacer()
        UIEnableToggle(accessibilityLabel: "开机时启动", isOn: $draft.launchAtLogin)
      }
      HStack {
        Text("显示 Dock 图标")
        Spacer()
        UIEnableToggle(accessibilityLabel: "显示 Dock 图标", isOn: $draft.showDockIcon)
      }
      if let error = model.systemBehaviorError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityLabel("系统设置未生效：\(error)")
      }
    }
  }

  private func kindBinding(_ kind: ClipboardContentKind) -> Binding<Bool> {
    Binding {
      draft.acceptedContentKinds.contains(kind)
    } set: { enabled in
      if enabled {
        draft.acceptedContentKinds.insert(kind)
      } else {
        draft.acceptedContentKinds.remove(kind)
      }
    }
  }

  private func symbol(for kind: ClipboardContentKind) -> String {
    switch kind {
    case .plainText: "doc.text"
    case .url: "link"
    case .file: "folder"
    case .richText: "textformat"
    }
  }

  private func summary(for kind: ClipboardContentKind) -> String {
    switch kind {
    case .plainText: "代码、命令和普通文本"
    case .url: "http 与 https 网页地址"
    case .file: "Finder 复制的文件或文件夹"
    case .richText: "邮件和文档中的文本内容"
    }
  }
}
