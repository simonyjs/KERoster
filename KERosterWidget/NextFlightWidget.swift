//
//  NextFlightWidget.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/03/02.
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - NextFlightEntry 정의 (날씨 관련 정보 제거)
struct NextFlightEntry: TimelineEntry {
    let date: Date
    let flightNumber: String
    let departure: String
    let arrival: String
    let departureDate: Date
    let remainingTime: TimeInterval
    
    // 추가 정보
    let depStnTime: String?
    let arrStnTime: String?
    let item: String?
    let dutyReport: String?
    
    // 새로 추가된 필드: Sdc와 Hotel (날씨 정보 제거)
    let sdc: String?
    let hotel: String?
}

// MARK: - 타임라인 프로바이더 정의
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
            dutyReport: "Duty Report",
            sdc: "Sdc Info",
            hotel: "Hotel Info"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        let now = Date()
        if let flight = loadNextFlight() {
            let entry = NextFlightEntry(
                date: now,
                flightNumber: flight.flightNumber,
                departure: flight.departure,
                arrival: flight.arrival,
                departureDate: flight.departureDate,
                remainingTime: flight.remainingTime,
                depStnTime: flight.depStnTime,
                arrStnTime: flight.arrStnTime,
                item: flight.item,
                dutyReport: flight.dutyReport,
                sdc: flight.sdc,
                hotel: flight.hotel
            )
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        } else {
            let entry = placeholder(in: context)
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
    
    // 기존 항공편 로드 함수 (날씨 관련은 변경 없음)
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
                            dutyReport: flight["DutyReport"],
                            sdc: flight["Sdc"],
                            hotel: flight["Hotel"]
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
    
    /// 남은 시간을 "Xd Yh" 또는 "Yh Zm"로 포맷
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
    
    /// 날짜를 "EEE, YYYY-MM-dd" 형식 문자열로 포맷
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY-MM-dd(EEE)"
        return formatter.string(from: date)
    }
    
    // 폰트 사이즈 multiplier: systemLarge에서 1.5, 나머지에서는 1.0
    var fontMultiplier: CGFloat {
        widgetFamily == .systemLarge ? 1.5 : 1.0
    }
    
    // 수정된 폰트들
    var dateFont: Font {
        // 기본 폰트 크기 (예: caption 사용)
        widgetFamily == .systemSmall ? .caption2 : .caption.bold()
    }
    
    var itemFont: Font {
        let captionSize = UIFont.preferredFont(forTextStyle: .caption1).pointSize * fontMultiplier
        return .system(size: captionSize)
    }
    
    // 공항 이름 폰트
    var mainTitleFont: Font {
        let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 1.2 * fontMultiplier
        return .system(size: baseSize, weight: .bold)
    }
    
    // 출발/도착 시간 폰트: systemLarge에서는 공항 이름과 같은 크기, 아니면 작은 폰트
    var airportTimeFont: Font {
        if widgetFamily == .systemLarge {
            return mainTitleFont
        } else {
            let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 1.2 / 3 * fontMultiplier
            return .system(size: baseSize)
        }
    }
    
    var subTitleFont: Font {
        widgetFamily == .systemSmall ? .caption : .subheadline
    }
    
    // "Show Up"과 "Time to DEP" 영역 폰트: systemLarge이면 현재 크기의 1.5배로 적용
    var timeLabelFont: Font {
        if widgetFamily == .systemLarge {
            return .system(size: 13 * 1.5, weight: .bold)
        } else {
            return widgetFamily == .systemSmall ? .caption2 : .footnote.bold()
        }
    }
    
    var timeValueFont: Font {
        if widgetFamily == .systemLarge {
            return .system(size: 13 * 1.5, weight: .bold)
        } else {
            return widgetFamily == .systemSmall ? .caption : .headline.bold()
        }
    }
    
    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
            
            VStack(spacing: 2) {
                // 상단 영역: 날짜 텍스트
                if widgetFamily == .systemLarge {
                    // 가장 큰 위젯에서는 날짜 폰트를 기본보다 2배 크기로 표시
                    Text(formatDate(entry.departureDate))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(formatDate(entry.departureDate))
                        .font(dateFont)
                        .bold()
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                
                if let item = entry.item, !item.isEmpty {
                    Text(item)
                        .font(itemFont)
                        .bold()
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                
                HStack(spacing: 2) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.departure)
                            .font(mainTitleFont)
                            .bold()
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(entry.depStnTime ?? "--:--")
                            .font(airportTimeFont)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Spacer()
                    Image(systemName: "airplane")
                        .foregroundColor(.blue)
                        .font(widgetFamily == .systemSmall ? .caption : .title2)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(entry.arrival)
                            .font(mainTitleFont)
                            .bold()
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(entry.arrStnTime ?? "--:--")
                            .font(airportTimeFont)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                
                // 중간 영역: DutyReport 및 Time to DEP
                HStack {
                    if let duty = entry.dutyReport, !duty.isEmpty {
                        VStack(spacing: 1) {
                            Text("Show Up")
                                .font(timeLabelFont)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                            Text(duty)
                                .font(timeLabelFont)
                                .bold()
                                .padding(4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(colorScheme == .dark ? .white : .blue)
                                .clipShape(Capsule())
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer().frame(maxWidth: .infinity)
                    }
                    
                    VStack(spacing: 1) {
                        Text("Time to DEP")
                            .font(timeLabelFont)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        Text(formatRemainingTime(entry.remainingTime))
                            .font(timeLabelFont)
                            .bold()
                            .padding(4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(colorScheme == .dark ? .white : .blue)
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                // 하단 영역: systemLarge 위젯에서만 추가 정보를 표시 (Sdc, Hotel)
                if widgetFamily == .systemLarge {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        if let sdc = entry.sdc, !sdc.isEmpty {
                            HStack {
                                Text("Sdc:")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.gray)
                                Text(sdc)
                                    .font(.caption.weight(.bold))
                            }
                        }
                        if let hotel = entry.hotel, !hotel.isEmpty {
                            HStack {
                                Text("Hotel:")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.gray)
                                Text(hotel)
                                    .font(.caption.weight(.bold))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.clear, for: .widget)
        .environment(\.dynamicTypeSize, .medium)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
