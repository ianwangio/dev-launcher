import DevLauncherCore
import SwiftUI

struct StatisticsView: View {
  @Bindable var model: AppModel
  @State private var granularity: ActivityStatisticsGranularity = .day
  @State private var selectedYear: Int
  @State private var selectedStart: Date?

  init(model: AppModel) {
    self.model = model
    _selectedYear = State(initialValue: model.statisticsCurrentYear)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          overview
          insights
          resultRatio
          aggregation
          actionRanking
          Label(
            "聚合统计不包含剪贴板内容、完整路径、命令参数或凭据。",
            systemImage: "info.circle"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: UISpacing.large) {
      Image(systemName: "chart.bar.xaxis")
        .font(.system(size: 23, weight: .semibold))
        .foregroundStyle(.blue)
        .frame(width: 52, height: 52)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: UISpacing.xSmall) {
        Text("统计概览").font(.title2.weight(.bold))
        Text("原始活动按上限保留，脱敏聚合统计永久保存。")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 3) {
        Text("最近一年").font(.callout.weight(.semibold))
        Text(recentRangeLabel).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(28)
  }

  private var overview: some View {
    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
      GridRow {
        MetricCard(title: "总执行", value: recent.totalCount.formatted())
        MetricCard(title: "成功执行", value: recent.succeededCount.formatted(), color: .green)
      }
      GridRow {
        MetricCard(title: "失败执行", value: recent.failedCount.formatted(), color: .orange)
        MetricCard(title: "活跃天数", value: recentDays.count.formatted())
      }
    }
  }

  private var insights: some View {
    HStack(spacing: 10) {
      InsightCard(
        title: "单日执行最多",
        value: maxDay.map { "\($0.totalCount.formatted()) 次" } ?? "—",
        note: maxDay.map { shortDate($0.start) } ?? "暂无数据"
      )
      InsightCard(
        title: "日均执行",
        value: recentDays.isEmpty
          ? "—" : String(format: "%.1f 次", Double(recent.totalCount) / Double(recentDays.count)),
        note: "按活跃日计算"
      )
      InsightCard(
        title: "成功率最高月份",
        value: bestMonth.map { percentage($0.successRate) } ?? "—",
        note: bestMonth.map { monthLabel($0.start) } ?? "暂无数据"
      )
      InsightCard(
        title: "最常用动作",
        value: recent.rankedActions.first?.name ?? "—",
        note: mostUsedActionNote
      )
    }
  }

  private var resultRatio: some View {
    VStack(spacing: 8) {
      HStack {
        Text("执行结果比例").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Spacer()
        Text("最近一年").font(.caption2).foregroundStyle(.secondary)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.orange.opacity(0.25))
          Capsule().fill(Color.blue)
            .frame(width: proxy.size.width * recent.successRate)
        }
      }
      .frame(height: 9)
      HStack {
        Text("成功 \(percentage(recent.successRate))").foregroundStyle(.blue)
        Spacer()
        Text("失败 \(percentage(recent.totalCount == 0 ? 0 : Double(recent.failedCount) / Double(recent.totalCount)))")
          .foregroundStyle(.orange)
      }
      .font(.caption2.weight(.bold))
    }
    .padding(14)
    .background(cardBackground)
  }

  private var aggregation: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Text("活动聚合").font(.headline)
        Picker("聚合粒度", selection: $granularity) {
          Text("按日").tag(ActivityStatisticsGranularity.day)
          Text("按月").tag(ActivityStatisticsGranularity.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
        .onChange(of: granularity) { _, _ in selectedStart = nil }
        Spacer()
        Picker("年份", selection: $selectedYear) {
          ForEach(model.statisticsAvailableYears, id: \.self) { year in
            Text(verbatim: "\(year) 年").tag(year)
          }
        }
        .labelsHidden()
        .frame(width: 110)
        .onChange(of: selectedYear) { _, _ in selectedStart = nil }
      }

      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: granularity == .day
              ? "\(selectedYear) 年每日活动"
              : "\(selectedYear) 年月度趋势")
              .font(.callout.weight(.semibold))
            Text(granularity == .day
              ? "全年按周横向排列，每周一列；颜色越深，执行次数越多"
              : "悬浮查看时间类型、总数、成功、失败和成功率")
              .font(.caption2).foregroundStyle(.secondary)
          }
          Spacer()
          if granularity == .month {
            HStack(spacing: 12) {
              Label("成功", systemImage: "square.fill").foregroundStyle(.green)
              Label("失败", systemImage: "square.fill").foregroundStyle(.orange)
            }
            .font(.caption2)
          }
        }
        .padding(16)
        Divider()
        if granularity == .day {
          YearHeatmap(
            year: selectedYear,
            calendar: model.statisticsCalendar,
            buckets: dailyBuckets,
            selectedStart: $selectedStart
          )
          .padding(16)
        } else {
          MonthChart(
            year: selectedYear,
            calendar: model.statisticsCalendar,
            buckets: monthlyBuckets,
            selectedStart: $selectedStart
          )
          .padding(.horizontal, 16)
          .padding(.bottom, 14)
        }
      }
      .background(cardBackground)

      detailPanel
    }
  }

  private var detailPanel: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(granularity == .day ? "当日详情" : "当月详情")
            .font(.callout.weight(.semibold))
          Text("所选时间的聚合结果").font(.caption2).foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(.horizontal, 16).padding(.vertical, 12)
      Divider()
      HStack(spacing: 12) {
        Text(detailDateLabel).font(.title3.weight(.bold)).frame(width: 160, alignment: .leading)
        DetailMetric(title: "总执行", value: detailBucket.totalCount.formatted())
        DetailMetric(title: "成功率", value: percentage(detailBucket.successRate), color: .green)
        DetailMetric(title: "成功", value: detailBucket.succeededCount.formatted(), color: .green)
        DetailMetric(title: "失败", value: detailBucket.failedCount.formatted(), color: .orange)
        Divider().frame(height: 54)
        VStack(alignment: .leading, spacing: 5) {
          Text("最常触发：\(detailBucket.rankedRules.first?.name ?? "—")")
          Text("最常使用：\(detailBucket.rankedActions.first?.name ?? "—")")
        }
        .font(.caption2).foregroundStyle(.secondary)
        .frame(width: 180, alignment: .leading)
      }
      .padding(16)
    }
    .background(cardBackground)
  }

  private var actionRanking: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("常用动作").font(.headline)
      VStack(spacing: 0) {
        if recent.rankedActions.isEmpty {
          Text("执行动作后，这里会显示最近一年的使用排行。")
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 58)
        } else {
          let top = Array(recent.rankedActions.prefix(3))
          let maximum = max(1, top.first?.count ?? 1)
          ForEach(Array(top.enumerated()), id: \.element.id) { index, item in
            HStack(spacing: 12) {
              Text("\(index + 1)").font(.caption).foregroundStyle(.tertiary).frame(width: 18)
              Text(item.name).font(.caption).frame(width: 160, alignment: .leading)
              GeometryReader { proxy in
                ZStack(alignment: .leading) {
                  Capsule().fill(Color.secondary.opacity(0.25))
                  Capsule().fill(rankColor(index))
                    .frame(width: proxy.size.width * Double(item.count) / Double(maximum))
                }
              }
              .frame(height: 6)
              Text(item.count.formatted()).font(.caption).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            }
            .frame(minHeight: 38)
          }
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 6)
      .background(cardBackground)
    }
  }

  private var recent: ActivityStatisticsBucket { model.recentStatistics }
  private var recentDays: [ActivityStatisticsBucket] { model.recentStatisticsDays }
  private var dailyBuckets: [ActivityStatisticsBucket] {
    model.statisticsBuckets(granularity: .day, year: selectedYear)
  }
  private var monthlyBuckets: [ActivityStatisticsBucket] {
    model.statisticsBuckets(granularity: .month, year: selectedYear)
  }
  private var detailBucket: ActivityStatisticsBucket {
    let buckets = granularity == .day ? dailyBuckets : monthlyBuckets
    if let selectedStart {
      return buckets.first(where: { $0.start == selectedStart })
        ?? ActivityStatisticsBucket(start: selectedStart)
    }
    return buckets.first ?? ActivityStatisticsBucket(start: fallbackStart)
  }
  private var fallbackStart: Date {
    model.statisticsCalendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))
      ?? .distantPast
  }
  private var detailDateLabel: String {
    granularity == .day ? shortDate(detailBucket.start) : monthLabel(detailBucket.start)
  }
  private var maxDay: ActivityStatisticsBucket? { recentDays.max { $0.totalCount < $1.totalCount } }
  private var bestMonth: ActivityStatisticsBucket? {
    model.statisticsAvailableYears
      .flatMap { model.statisticsBuckets(granularity: .month, year: $0) }
      .filter { $0.totalCount > 0 && $0.start >= model.recentStatisticsInterval.start }
      .max { lhs, rhs in
        lhs.successRate == rhs.successRate ? lhs.totalCount < rhs.totalCount : lhs.successRate < rhs.successRate
      }
  }
  private var mostUsedActionNote: String {
    guard let action = recent.rankedActions.first, recent.totalCount > 0 else { return "暂无数据" }
    return "占全部动作 \(Int((Double(action.count) / Double(recent.totalCount) * 100).rounded()))%"
  }
  private var recentRangeLabel: String {
    "\(shortDate(model.recentStatisticsInterval.start)) – \(shortDate(model.recentStatisticsInterval.end))"
  }
  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color(nsColor: .controlBackgroundColor))
      .stroke(Color.primary.opacity(0.12), lineWidth: 1)
  }
  private func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
  }
  private func monthLabel(_ date: Date) -> String {
    date.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN")))
  }
  private func percentage(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
  private func rankColor(_ index: Int) -> Color { [.blue, .green, .orange][min(index, 2)] }
}

private struct MetricCard: View {
  let title: String
  let value: String
  var color: Color = .primary

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(color)
    }
    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
  }
}

private struct InsightCard: View {
  let title: String
  let value: String
  let note: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
      Text(value).font(.headline).lineLimit(1)
      Text(note).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .padding(13)
    .background(
      RoundedRectangle(cornerRadius: 11).fill(Color(nsColor: .controlBackgroundColor))
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
  }
}

private struct DetailMetric: View {
  let title: String
  let value: String
  var color: Color = .primary

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.headline).foregroundStyle(color)
    }
    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .padding(10)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
  }
}

private struct HeatmapSlot: Identifiable {
  let index: Int
  let date: Date?
  var id: Int { index }
}

private struct YearHeatmap: View {
  let year: Int
  let calendar: Calendar
  let buckets: [ActivityStatisticsBucket]
  @Binding var selectedStart: Date?

  private let gap: CGFloat = 2
  private let labelWidth: CGFloat = 18

  var body: some View {
    GeometryReader { proxy in
      let columns = max(1, slots.count / 7)
      let cell = min(12, max(7, (proxy.size.width - labelWidth - 8 - gap * CGFloat(columns - 1)) / CGFloat(columns)))
      VStack(alignment: .leading, spacing: 6) {
        ZStack(alignment: .leading) {
          ForEach(monthPositions, id: \.month) { item in
            Text("\(item.month)月")
              .font(.system(size: 9))
              .foregroundStyle(.secondary)
              .offset(x: labelWidth + 8 + CGFloat(item.column) * (cell + gap))
          }
        }
        .frame(height: 12)
        HStack(alignment: .top, spacing: 8) {
          VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
              Text(["一", "", "三", "", "五", "", "日"][row])
                .font(.system(size: 8)).foregroundStyle(.secondary)
                .frame(width: labelWidth, height: cell)
            }
          }
          LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 7), spacing: gap) {
            ForEach(slots) { slot in
              if let date = slot.date {
                let bucket = bucketByDay[date]
                Button { selectedStart = date } label: {
                  RoundedRectangle(cornerRadius: 2)
                    .fill(heatColor(bucket?.totalCount ?? 0))
                    .overlay {
                      if selectedStart == date {
                        RoundedRectangle(cornerRadius: 2).stroke(Color.primary, lineWidth: 1.5)
                      }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: cell, height: cell)
                .help("\(date.formatted(date: .long, time: .omitted)) · \((bucket?.totalCount ?? 0).formatted()) 次执行")
                .accessibilityLabel("\(date.formatted(date: .long, time: .omitted))，\((bucket?.totalCount ?? 0).formatted()) 次执行")
              } else {
                Color.clear.frame(width: cell, height: cell)
              }
            }
          }
        }
        HStack(spacing: 4) {
          Spacer()
          Text("少")
          ForEach(0..<5, id: \.self) { level in
            RoundedRectangle(cornerRadius: 2).fill(legendColor(level)).frame(width: 10, height: 10)
          }
          Text("多")
        }
        .font(.system(size: 9)).foregroundStyle(.secondary)
      }
    }
    .frame(height: 126)
  }

  private var bucketByDay: [Date: ActivityStatisticsBucket] {
    Dictionary(uniqueKeysWithValues: buckets.map { (calendar.startOfDay(for: $0.start), $0) })
  }
  private var maximum: Int { max(1, buckets.map(\.totalCount).max() ?? 1) }
  private var slots: [HeatmapSlot] {
    guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
      let nextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)),
      let gridStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start
    else { return [] }
    let dayCount = calendar.dateComponents([.day], from: gridStart, to: nextYear).day ?? 0
    let slotCount = Int(ceil(Double(dayCount) / 7.0)) * 7
    return (0..<slotCount).map { index in
      guard let date = calendar.date(byAdding: .day, value: index, to: gridStart),
        date >= first, date < nextYear
      else { return HeatmapSlot(index: index, date: nil) }
      return HeatmapSlot(index: index, date: date)
    }
  }
  private var monthPositions: [(month: Int, column: Int)] {
    guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
      let gridStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start
    else { return [] }
    return (1...12).compactMap { month in
      guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
      let days = calendar.dateComponents([.day], from: gridStart, to: start).day ?? 0
      return (month, days / 7)
    }
  }
  private func heatColor(_ count: Int) -> Color {
    guard count > 0 else { return Color.secondary.opacity(0.12) }
    let ratio = Double(count) / Double(maximum)
    if ratio <= 0.25 { return Color.green.opacity(0.28) }
    if ratio <= 0.5 { return Color.green.opacity(0.48) }
    if ratio <= 0.75 { return Color.green.opacity(0.7) }
    return Color.green
  }
  private func legendColor(_ level: Int) -> Color {
    level == 0 ? Color.secondary.opacity(0.12) : Color.green.opacity(0.18 + Double(level) * 0.2)
  }
}

private struct MonthChart: View {
  let year: Int
  let calendar: Calendar
  let buckets: [ActivityStatisticsBucket]
  @Binding var selectedStart: Date?
  @State private var hoveredStart: Date?

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      ForEach(months) { bucket in
        VStack(spacing: 6) {
          ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5)
              .fill(Color.secondary.opacity(0.14))
              .frame(height: barHeight(bucket))
            VStack(spacing: 0) {
              Rectangle().fill(Color.orange).frame(height: failureHeight(bucket))
              Rectangle().fill(Color.green)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .frame(height: barHeight(bucket))
            if selectedStart == bucket.start {
              RoundedRectangle(cornerRadius: 5).stroke(Color.primary, lineWidth: 2)
                .frame(height: barHeight(bucket))
            }
          }
          Text("\(calendar.component(.month, from: bucket.start)) 月")
            .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selectedStart = bucket.start }
        .onHover { hovering in hoveredStart = hovering ? bucket.start : nil }
        .overlay(alignment: .top) {
          if hoveredStart == bucket.start {
            MonthTooltip(bucket: bucket, calendar: calendar)
              .offset(y: -2)
              .zIndex(5)
          }
        }
        .zIndex(hoveredStart == bucket.start ? 5 : 0)
      }
    }
    .padding(.top, 68)
    .frame(height: 236, alignment: .bottom)
  }

  private var months: [ActivityStatisticsBucket] {
    let byMonth = Dictionary(uniqueKeysWithValues: buckets.map { (calendar.component(.month, from: $0.start), $0) })
    return (1...12).compactMap { month in
      guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
      return byMonth[month] ?? ActivityStatisticsBucket(start: start)
    }
  }
  private var maximum: Int { max(1, months.map(\.totalCount).max() ?? 1) }
  private func barHeight(_ bucket: ActivityStatisticsBucket) -> CGFloat {
    max(10, CGFloat(bucket.totalCount) / CGFloat(maximum) * 130)
  }
  private func failureHeight(_ bucket: ActivityStatisticsBucket) -> CGFloat {
    guard bucket.totalCount > 0 else { return 0 }
    return barHeight(bucket) * CGFloat(bucket.failedCount) / CGFloat(bucket.totalCount)
  }
}

private struct MonthTooltip: View {
  let bucket: ActivityStatisticsBucket
  let calendar: Calendar

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(verbatim: "\(calendar.component(.year, from: bucket.start)) 年 \(calendar.component(.month, from: bucket.start)) 月")
        .font(.caption.weight(.semibold))
      Text("时间类型：按月")
      Text("总执行 \(bucket.totalCount) · 成功 \(bucket.succeededCount) · 失败 \(bucket.failedCount)")
      Text("成功率 \(String(format: "%.1f%%", bucket.successRate * 100))").foregroundStyle(.green)
    }
    .font(.caption2)
    .padding(9)
    .frame(width: 172, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.18)))
    .shadow(radius: 8, y: 4)
  }
}
