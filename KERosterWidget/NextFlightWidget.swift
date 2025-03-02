//
//  NextFlightWidget.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/03/02.
//

import WidgetKit
import SwiftUI
import UIKit  // UIFont를 사용하기 위해 추가

// MARK: - 타임라인 엔트리 정의
/// 위젯에 표시할 항공편 정보와 추가 데이터를 저장하는 구조체
struct NextFlightEntry: TimelineEntry {
    let date: Date                // 위젯 갱신 기준 시간 (현재 시간)
    let flightNumber: String      // 항공편 번호 ("FlightNumber" 또는 "Item")
    let departure: String         // 출발 공항 ("DepAp")
    let arrival: String           // 도착 공항 ("ArrAp")
    let departureDate: Date       // 출발 날짜와 시간 ("DepDate" + "DepStnTime")
    let remainingTime: TimeInterval // 현재 시간부터 출발까지 남은 시간 (초 단위)
    
    // 추가 정보 (있으면 표시)
    let depStnTime: String?       // 출발 시각 (DepStnTime)
    let arrStnTime: String?       // 도착 시각 (ArrStnTime)
    let item: String?             // 항공편 코드 (예: KE123)
}

// MARK: - 타임라인 프로바이더 정의
/// App Group의 UserDefaults("group.org.duckdns.cageyjs.KERoster")를 사용하여
/// 저장된 스케줄 데이터에서 WorkType이 "FLY" 또는 "TVL"인 항공편 중 현재 시간 이후의 항공편을 찾아
/// 타임라인 엔트리(NextFlightEntry)로 변환하는 역할을 수행함.
struct NextFlightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(
            date: Date(),
            flightNumber: "KE123",
            departure: "ICN",
            arrival: "PEK",
            departureDate: Date().addingTimeInterval(86400 * 9 + 7200), // 9일 2시간 후
            remainingTime: 86400 * 9 + 7200,
            depStnTime: "07:55",
            arrStnTime: "09:25",
            item: "KE123"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        let now = Date()
        if let nextFlight = loadNextFlight() {
            let entry = nextFlight
            // 5분 후에 타임라인 갱신 (필요에 따라 조정)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        } else {
            // 스케줄 데이터가 없으면 placeholder 사용
            let entry = placeholder(in: context)
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
    
    /// 공유 UserDefaults(App Group)를 통해 저장된 스케줄 데이터를 읽어와,
    /// WorkType이 "FLY" 또는 "TVL"인 항공편 중 현재 시간 이후의 항공편을 찾아 타임라인 엔트리로 변환하는 함수
    func loadNextFlight() -> NextFlightEntry? {
        guard let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
              let data = sharedDefaults.data(forKey: "schedules") else {
            print("스케줄 데이터가 저장되어 있지 않음")
            return nil
        }
        
        do {
            let schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "dd-MMM-yyyy HH:mm"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            var candidates: [NextFlightEntry] = []
            
            for (_, flights) in schedules {
                for flight in flights {
                    // WorkType이 "FLY" 또는 "TVL"인 항공편만 선택
                    guard let workType = flight["WorkType"],
                          (workType == "FLY" || workType == "TVL") else { continue }
                    
                    guard let depTimeStr = flight["DepStnTime"],
                          let depDateStr = flight["DepDate"],
                          let departureDate = formatter.date(from: "\(depDateStr) \(depTimeStr)") else { continue }
                    
                    if departureDate > now {
                        let remaining = departureDate.timeIntervalSince(now)
                        let entry = NextFlightEntry(
                            date: now,
                            flightNumber: flight["FlightNumber"] ?? flight["Item"] ?? "N/A",
                            departure: flight["DepAp"] ?? "N/A",
                            arrival: flight["ArrAp"] ?? "N/A",
                            departureDate: departureDate,
                            remainingTime: remaining,
                            depStnTime: depTimeStr,
                            arrStnTime: flight["ArrStnTime"],
                            item: flight["Item"]
                        )
                        candidates.append(entry)
                    }
                }
            }
            return candidates.sorted(by: { $0.departureDate < $1.departureDate }).first
        } catch {
            print("스케줄 데이터 디코딩 에러: \(error)")
            return nil
        }
    }
}

// MARK: - 위젯 엔트리 뷰 정의
/// 위젯에 표시될 UI를 SwiftUI로 구성하며, 크기에 따라 표시되는 정보를 다르게 처리함.
struct NextFlightWidgetEntryView: View {
    var entry: NextFlightEntry
    @Environment(\.widgetFamily) var widgetFamily
    
    /// 남은 시간을 "Xd Yh" 또는 "Yh" 형식으로 변환하는 함수
    func formatRemainingTime(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        return days > 0 ? "\(days)일 \(hours)시간" : "\(hours)시간"
    }
    
    /// 날짜를 "EEEE dd MMM" 형식 (예: Tuesday 04 Mar)으로 포맷하는 함수
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE dd MMM"
        return formatter.string(from: date)
    }
    
    // 위젯 크기에 따라 글자 크기를 조절하기 위한 폰트 변수들
    var dateFont: Font {
        widgetFamily == .systemSmall ? .caption2 : .caption
    }
    
    var itemFont: Font {
        let captionSize = UIFont.preferredFont(forTextStyle: .caption1).pointSize
        let multiplier: CGFloat = widgetFamily == .systemSmall ? 1.5 : 2.0
        return .system(size: captionSize * multiplier)
    }
    
    var mainTitleFont: Font {
        widgetFamily == .systemSmall ? .headline : .title
    }
    
    var subTitleFont: Font {
        widgetFamily == .systemSmall ? .caption : .subheadline
    }
    
    var timeLabelFont: Font {
        widgetFamily == .systemSmall ? .caption2 : .footnote
    }
    
    var timeValueFont: Font {
        widgetFamily == .systemSmall ? .caption : .headline
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // 상단: 출발 날짜와 Item 표시
            Text(formatDate(entry.departureDate))
                .font(dateFont)
                .bold() // 날짜를 굵게 표시
                .foregroundColor(.gray)
            if let item = entry.item, !item.isEmpty {
                Text(item)
                    .font(itemFont)
                    .foregroundColor(.blue) // Item을 파란색으로 표시
            }
            
            // 중간: 항공편 정보 (출발 공항, 도착 공항, 아이콘 포함)
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.departure)
                        .font(mainTitleFont)
                        .bold()
                        .foregroundColor(.primary)
                    Text(entry.depStnTime ?? "--:--")
                        .font(subTitleFont)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "airplane")
                    .foregroundColor(.blue)
                    .font(widgetFamily == .systemSmall ? .caption : .title2)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.arrival)
                        .font(mainTitleFont)
                        .bold()
                        .foregroundColor(.primary)
                    Text(entry.arrStnTime ?? "--:--")
                        .font(subTitleFont)
                        .foregroundColor(.secondary)
                }
            }
            
            // 하단: "Time to Departure"와 남은 시간 표시
            HStack(spacing: 2) {
                Text("Time to Departure ")
                    .font(timeLabelFont)
                    .foregroundColor(.secondary)
                Text(formatRemainingTime(entry.remainingTime))
                    .font(timeValueFont)
                    .bold()
                    .foregroundColor(.blue)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Group {
                if #available(iOS 17.0, *) {
                    Color.clear.containerBackground(.fill, for: .widget)
                } else {
                    Color.white
                }
            }
        )
    }
}

// MARK: - 위젯 정의
/// NextFlightWidget 위젯을 정의 (개별 위젯에서는 @main을 사용하지 않음)
struct NextFlightWidget: Widget {
    let kind: String = "NextFlightWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextFlightTimelineProvider()) { entry in
            NextFlightWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Flight")
        .description("Displays upcoming flight details for FLY/TVL work types with remaining time until departure.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
