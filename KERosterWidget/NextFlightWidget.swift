//
//  NextFlightWidget.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/03/02.
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - NextFlightEntry 정의 (두 번째, 세 번째 항공편 정보를 위한 필드 추가)
struct NextFlightEntry: TimelineEntry {
    let date: Date
    // 첫 번째 항공편 정보
    let flightNumber: String
    let departure: String
    let arrival: String
    let departureDate: Date
    let remainingTime: TimeInterval
    let depStnTime: String?
    let arrStnTime: String?
    let item: String?
    let dutyReport: String?
    
    // 두 번째 항공편 정보
    let secondFlightNumber: String?
    let secondDeparture: String?
    let secondArrival: String?
    let secondDepartureDate: Date?
    let secondDepStnTime: String?
    let secondArrStnTime: String?
    let secondItem: String?
    
    // 세 번째 항공편 정보
    let thirdFlightNumber: String?
    let thirdDeparture: String?
    let thirdArrival: String?
    let thirdDepartureDate: Date?
    let thirdDepStnTime: String?
    let thirdArrStnTime: String?
    let thirdItem: String?
}

// MARK: - 타임라인 프로바이더 정의
struct NextFlightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(
            date: Date(),
            flightNumber: "KE017",
            departure: "ICN",
            arrival: "LAX",
            departureDate: Date().addingTimeInterval(86400 * 9 + 7200), // 9일 2시간 후
            remainingTime: 86400 * 9 + 7200,
            depStnTime: "12:00",
            arrStnTime: "08:00",
            item: "KE017",
            dutyReport: "Duty Report",
            secondFlightNumber: "KE081",
            secondDeparture: "ICN",
            secondArrival: "JFK",
            secondDepartureDate: Date().addingTimeInterval(86400 * 10 + 3600), // 10일 1시간 후
            secondDepStnTime: "14:00",
            secondArrStnTime: "20:00",
            secondItem: "KE081",
            thirdFlightNumber: "KE901",
            thirdDeparture: "ICN",
            thirdArrival: "CDG",
            thirdDepartureDate: Date().addingTimeInterval(86400 * 11 + 1800), // 11일 0.5시간 후
            thirdDepStnTime: "16:00",
            thirdArrStnTime: "22:00",
            thirdItem: "KE901"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        let now = Date()
        if let entry = loadUpcomingFlights() {
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        } else {
            let entry = placeholder(in: context)
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
    
    // 스케줄 데이터를 불러와 가장 빠른 항공편, 두 번째 항공편, 세 번째 항공편 정보를 결합하여 엔트리를 생성
    func loadUpcomingFlights() -> NextFlightEntry? {
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
                            secondFlightNumber: nil,
                            secondDeparture: nil,
                            secondArrival: nil,
                            secondDepartureDate: nil,
                            secondDepStnTime: nil,
                            secondArrStnTime: nil,
                            secondItem: nil,
                            thirdFlightNumber: nil,
                            thirdDeparture: nil,
                            thirdArrival: nil,
                            thirdDepartureDate: nil,
                            thirdDepStnTime: nil,
                            thirdArrStnTime: nil,
                            thirdItem: nil
                        )
                        candidates.append(entry)
                    }
                }
            }
            let sortedCandidates = candidates.sorted(by: { $0.departureDate < $1.departureDate })
            guard let firstFlight = sortedCandidates.first else {
                return nil
            }
            let secondFlight = sortedCandidates.count > 1 ? sortedCandidates[1] : nil
            let thirdFlight = sortedCandidates.count > 2 ? sortedCandidates[2] : nil
            
            // 첫 번째, 두 번째, 세 번째 항공편 정보를 결합하여 엔트리 생성
            let combinedEntry = NextFlightEntry(
                date: now,
                flightNumber: firstFlight.flightNumber,
                departure: firstFlight.departure,
                arrival: firstFlight.arrival,
                departureDate: firstFlight.departureDate,
                remainingTime: firstFlight.remainingTime,
                depStnTime: firstFlight.depStnTime,
                arrStnTime: firstFlight.arrStnTime,
                item: firstFlight.item,
                dutyReport: firstFlight.dutyReport,
                secondFlightNumber: secondFlight?.flightNumber,
                secondDeparture: secondFlight?.departure,
                secondArrival: secondFlight?.arrival,
                secondDepartureDate: secondFlight?.departureDate,
                secondDepStnTime: secondFlight?.depStnTime,
                secondArrStnTime: secondFlight?.arrStnTime,
                secondItem: secondFlight?.item,
                thirdFlightNumber: thirdFlight?.flightNumber,
                thirdDeparture: thirdFlight?.departure,
                thirdArrival: thirdFlight?.arrival,
                thirdDepartureDate: thirdFlight?.departureDate,
                thirdDepStnTime: thirdFlight?.depStnTime,
                thirdArrStnTime: thirdFlight?.arrStnTime,
                thirdItem: thirdFlight?.item
            )
            
            return combinedEntry
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
    
    /// 남은 시간을 "Xd Yh" 또는 "Yh Zm" 형식으로 포맷
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
    
    // 폰트 사이즈 multiplier: systemLarge에서 1.5, 그 외는 1.0
    var fontMultiplier: CGFloat {
        widgetFamily == .systemLarge ? 1.5 : 1.0
    }
    
    // 수정된 폰트들
    var dateFont: Font {
        widgetFamily == .systemSmall ? .caption2 : .caption.bold()
    }
    
    var itemFont: Font {
        let captionSize = UIFont.preferredFont(forTextStyle: .caption1).pointSize * fontMultiplier
        return .system(size: captionSize)
    }
    
    var mainTitleFont: Font {
        let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 1.2 * fontMultiplier
        return .system(size: baseSize, weight: .bold)
    }
    
    // 기존 airportTimeFont를 systemLarge일 경우 1.2배 크기로 줄임
    var airportTimeFont: Font {
        if widgetFamily == .systemLarge {
            let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 1.2 * fontMultiplier * 1.2
            return .system(size: baseSize, weight: .bold)
        } else {
            let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 1.2 / 2 * fontMultiplier
            return .system(size: baseSize, weight: .bold)
        }
    }
    
    var subTitleFont: Font {
        widgetFamily == .systemSmall ? .caption : .subheadline
    }
    
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
        // TimelineView를 사용해 실시간 카운트다운 구현 (1초마다 업데이트)
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let now = context.date
            let remaining = entry.departureDate.timeIntervalSince(now)
            
            ZStack {
                Color.clear
                    .ignoresSafeArea()
                
                VStack(spacing: 2) {
                    // 상단 영역: 첫 번째 항공편 정보
                    if widgetFamily == .systemLarge {
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
                        VStack(alignment: .center, spacing: 1) {
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
                        VStack(alignment: .center, spacing: 1) {
                            Text(entry.arrival)
                                .font(mainTitleFont)
                                .bold()
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(entry.arrStnTime ?? "--:--")
                                .font(airportTimeFont)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    
                    // 중간 영역: DutyReport 및 실시간 Time to DEP 표시
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
                            Text(formatRemainingTime(remaining))
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
                    
                    // 하단 영역: systemLarge 위젯에서 두 번째와 세 번째 항공편 정보를 두 칼럼으로 표시
                    if widgetFamily == .systemLarge && (entry.secondDepartureDate != nil || entry.thirdDepartureDate != nil) {
                        Divider()
                        HStack {
                            // 왼쪽 셀: 두 번째 항공편 정보
                            if let secondDate = entry.secondDepartureDate {
                                VStack(spacing: 2) {
                                    Text(formatDate(secondDate))
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                    if let secondItem = entry.secondItem, !secondItem.isEmpty {
                                        Text(secondItem)
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.blue)
                                            .multilineTextAlignment(.center)
                                    }
                                    HStack {
                                        VStack(spacing: 1) {
                                            Text(entry.secondDeparture ?? "N/A")
                                                .font(.headline)
                                                .bold()
                                                .multilineTextAlignment(.center)
                                            Text(entry.secondDepStnTime ?? "--:--")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .multilineTextAlignment(.center)
                                        }
                                        Image(systemName: "airplane")
                                            .foregroundColor(.blue)
                                        VStack(spacing: 1) {
                                            Text(entry.secondArrival ?? "N/A")
                                                .font(.headline)
                                                .bold()
                                                .multilineTextAlignment(.center)
                                            Text(entry.secondArrStnTime ?? "--:--")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Spacer().frame(maxWidth: .infinity)
                            }
                            
                            // 오른쪽 셀: 세 번째 항공편 정보
                            if let thirdDate = entry.thirdDepartureDate {
                                VStack(spacing: 2) {
                                    Text(formatDate(thirdDate))
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                    if let thirdItem = entry.thirdItem, !thirdItem.isEmpty {
                                        Text(thirdItem)
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.blue)
                                            .multilineTextAlignment(.center)
                                    }
                                    HStack {
                                        VStack(spacing: 1) {
                                            Text(entry.thirdDeparture ?? "N/A")
                                                .font(.headline)
                                                .bold()
                                                .multilineTextAlignment(.center)
                                            Text(entry.thirdDepStnTime ?? "--:--")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .multilineTextAlignment(.center)
                                        }
                                        Image(systemName: "airplane")
                                            .foregroundColor(.blue)
                                        VStack(spacing: 1) {
                                            Text(entry.thirdArrival ?? "N/A")
                                                .font(.headline)
                                                .bold()
                                                .multilineTextAlignment(.center)
                                            Text(entry.thirdArrStnTime ?? "--:--")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Spacer().frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.clear, for: .widget)
            .environment(\.dynamicTypeSize, .medium)
        }
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
        .description("Displays upcoming flight details for FLY/TVL work types with real-time countdown. Large widget shows second and third flights side by side.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
