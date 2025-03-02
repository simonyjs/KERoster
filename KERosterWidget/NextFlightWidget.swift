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
    let dutyReport: String?       // DutyReport (있을 경우 표기)
}

// MARK: - 타임라인 프로바이더 정의
/// App Group의 UserDefaults("group.org.duckdns.cageyjs.KERoster")를 사용하여
/// 저장된 스케줄 데이터에서 WorkType이 "FLY" 또는 "TVL"인 항공편 중
/// 현재 시간 이후의 항공편을 찾아 타임라인 엔트리(NextFlightEntry)로 변환하는 역할을 수행함.
struct NextFlightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(
            date: Date(),
            flightNumber: "KE123",
            departure: "ICN",
            arrival: "LAX",
            departureDate: Date().addingTimeInterval(86400 * 9 + 7200), // 9일 2시간 후
            remainingTime: 86400 * 9 + 7200,
            depStnTime: "12:00",
            arrStnTime: "08:00",
            item: "KE123",
            dutyReport: "Duty Report" // 예시
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        let now = Date()
        if let nextFlight = loadNextFlight() {
            let entry = nextFlight
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        } else {
            let entry = placeholder(in: context)
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
    
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
                            item: flight["Item"],
                            dutyReport: flight["DutyReport"]
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
struct NextFlightWidgetEntryView: View {
    var entry: NextFlightEntry
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.colorScheme) var colorScheme
    
    /// 남은 시간을 24시간 초과이면 "Xd Yh" 형식, 24시간 이내이면 "Yh Zm" 형식으로 변환하는 함수
    func formatRemainingTime(_ interval: TimeInterval) -> String {
        if interval > 86400 {
            let days = Int(interval) / 86400
            let hours = (Int(interval) % 86400) / 3600
            return "\(days)d \(hours)h"
        } else {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
    
    /// 날짜를 "EEEE, dd-MMM" 형식으로 포맷하는 함수
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, dd-MMM"
        return formatter.string(from: date)
    }
    
    // 위젯 크기에 따라 폰트 조절
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
        ZStack {
            // 투명 배경: containerBackground API를 사용해 투명하게 처리
            Color.clear
                .ignoresSafeArea()
            
            VStack(spacing: 4) {
                // 날짜 표시 (다크/라이트 모드에 따라 색상 조절)
                Text(formatDate(entry.departureDate))
                    .font(dateFont)
                    .bold()
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                if let item = entry.item, !item.isEmpty {
                    Text(item)
                        .font(itemFont)
                        .bold()
                        .foregroundColor(.blue)
                }
                
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.departure)
                            .font(mainTitleFont)
                            .bold()
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        Text(entry.depStnTime ?? "--:--")
                            .font(subTitleFont)
                            .foregroundColor(.gray)
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
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        Text(entry.arrStnTime ?? "--:--")
                            .font(subTitleFont)
                            .foregroundColor(.gray)
                    }
                }
                
                // 하단: 좌측은 DutyReport 영역, 우측은 Time to Departure 영역을 양쪽으로 배분
                HStack {
                    if let duty = entry.dutyReport, !duty.isEmpty {
                        VStack(spacing: 2) {
                            Text("Show Up")
                                .font(timeLabelFont)
                                .foregroundColor(.gray)
                            Text(duty)
                                .font(timeLabelFont)
                                .bold()
                                .padding(4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(colorScheme == .dark ? .white : .blue)
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // dutyReport가 없으면 빈 공간
                        Spacer().frame(maxWidth: .infinity)
                    }
                    
                    VStack(spacing: 2) {
                        Text("Time to Departure")
                            .font(timeLabelFont)
                            .foregroundColor(.gray)
                        Text(formatRemainingTime(entry.remainingTime))
                            .font(timeValueFont)
                            .bold()
                            .padding(4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(colorScheme == .dark ? .white : .blue)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // containerBackground API를 사용해 투명하게 처리
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - 위젯 정의
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
