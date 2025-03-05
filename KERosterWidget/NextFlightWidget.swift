//
//  NextFlightWidget.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/03/02.
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - FlightInfo: 저장된 스케줄 정보를 위한 구조체 (워크타입 무관)
struct FlightInfo: Identifiable {
    let id = UUID()
    let flightNumber: String
    let departure: String
    let arrival: String
    let departureDate: Date
    let depStnTime: String?
    let arrStnTime: String?
    let item: String?
    // 추가 필드
    let workType: String?
    let activity: String?
    
    // 미리 세부사항 문자열을 생성하는 함수
    func detailText() -> String {
        // workType이 있으면 "출발공항(출발시간)-도착공항(도착시간)" 형식으로 표시
        if let wt = workType, !wt.isEmpty {
            let depTime = depStnTime ?? "--:--"
            let arrTime = arrStnTime ?? "--:--"
            return "\(departure)(\(depTime))-\(arrival)(\(arrTime))"
        } else {
            // workType이 없으면 activity 값을 반환 (activity가 없으면 빈 문자열 반환)
            if let act = activity, !act.isEmpty {
                return act
            } else {
                return ""
            }
        }
    }
}


// MARK: - NextFlightEntry 정의 (이전, 현재, 다음 항공편 정보를 위한 필드 및 미디움 오른쪽 셀에 사용할 otherFlights)
struct NextFlightEntry: TimelineEntry {
    let date: Date
    // 현재(가장 빠른) 항공편 정보 (기존 워크타입 FLY/TVL 필터 적용)
    let flightNumber: String
    let departure: String
    let arrival: String
    let departureDate: Date
    let remainingTime: TimeInterval
    let depStnTime: String?
    let arrStnTime: String?
    let item: String?
    let dutyReport: String?
    
    // 이전 항공편 정보 (과거 항공편)
    let previousFlightNumber: String?
    let previousDeparture: String?
    let previousArrival: String?
    let previousDepartureDate: Date?
    let previousDepStnTime: String?
    let previousArrStnTime: String?
    let previousItem: String?
    
    // 다음 항공편 정보 (현재 항공편 이후)
    let nextFlightNumber: String?
    let nextDeparture: String?
    let nextArrival: String?
    let nextDepartureDate: Date?
    let nextDepStnTime: String?
    let nextArrStnTime: String?
    let nextItem: String?
    
    // 미디움 위젯 오른쪽 셀에 표시할, 저장되어 있는 모든 스케줄 중 오늘 이후 출발하는 상위 3개 항목 (워크타입 무관)
    let otherFlights: [FlightInfo]?
}

// MARK: - 타임라인 프로바이더 정의
struct NextFlightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(
            date: Date(),
            flightNumber: "KE017",
            departure: "ICN",
            arrival: "LAX",
            departureDate: Date().addingTimeInterval(86400 * 9 + 7200),
            remainingTime: 86400 * 9 + 7200,
            depStnTime: "12:00",
            arrStnTime: "08:00",
            item: "KE017",
            dutyReport: "Duty Report",
            previousFlightNumber: "KE001",
            previousDeparture: "SFO",
            previousArrival: "ICN",
            previousDepartureDate: Date().addingTimeInterval(-3600),
            previousDepStnTime: "10:00",
            previousArrStnTime: "18:00",
            previousItem: "KE001",
            nextFlightNumber: "KE081",
            nextDeparture: "ICN",
            nextArrival: "JFK",
            nextDepartureDate: Date().addingTimeInterval(86400 * 10 + 3600),
            nextDepStnTime: "14:00",
            nextArrStnTime: "20:00",
            nextItem: "KE081",
            otherFlights: [
                FlightInfo(flightNumber: "KE101", departure: "ICN", arrival: "FRA", departureDate: Date().addingTimeInterval(3600), depStnTime: "09:00", arrStnTime: "15:00", item: "KE101", workType: nil, activity: "Activity A"),
                FlightInfo(flightNumber: "KE202", departure: "FRA", arrival: "LHR", departureDate: Date().addingTimeInterval(7200), depStnTime: "11:00", arrStnTime: "12:00", item: "KE202", workType: "FLY", activity: nil),
                FlightInfo(flightNumber: "KE303", departure: "LHR", arrival: "JFK", departureDate: Date().addingTimeInterval(10800), depStnTime: "13:00", arrStnTime: "16:00", item: "KE303", workType: nil, activity: "Activity B")
            ]
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        let now = Date()
        if let entry = loadFlights() {
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        } else {
            let entry = placeholder(in: context)
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
    
    // 모든 스케줄(워크타입 무관) 정보를 불러와 정렬된 FlightInfo 배열을 반환하는 함수 (이제 loadAllSKD())
    func loadAllSKD() -> [FlightInfo] {
        guard let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
              let data = sharedDefaults.data(forKey: "schedules") else {
            print("스케줄 데이터가 저장되어 있지 않음")
            return []
        }
        
        do {
            let schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            let formatter = DateFormatter()
            formatter.dateFormat = "dd-MMM-yyyy HH:mm"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            var allFlights: [FlightInfo] = []
            
            for (_, flights) in schedules {
                for flight in flights {
                    guard let depTimeStr = flight["DepStnTime"],
                          let depDateStr = flight["DepDate"],
                          let departureDate = formatter.date(from: "\(depDateStr) \(depTimeStr)") else { continue }
                    
                    let info = FlightInfo(
                        flightNumber: flight["FlightNumber"] ?? flight["Item"] ?? "N/A",
                        departure: flight["DepAp"] ?? "N/A",
                        arrival: flight["ArrAp"] ?? "N/A",
                        departureDate: departureDate,
                        depStnTime: depTimeStr,
                        arrStnTime: flight["ArrStnTime"],
                        item: flight["Item"],
                        workType: flight["WorkType"],
                        activity: flight["Activity"]
                    )
                    allFlights.append(info)
                }
            }
            // 출발시간 기준 오름차순 정렬
            allFlights.sort { $0.departureDate < $1.departureDate }
            return allFlights
        } catch {
            print("스케줄 데이터 디코딩 에러: \(error)")
            return []
        }
    }
    
    // 기존 워크타입(Fly/TVL) 필터 적용 항공편과 함께,
    // 저장되어 있는 모든 스케줄 중 오늘 이후 출발하는 상위 3개 항목을 otherFlights에 저장하여 엔트리를 생성
    func loadFlights() -> NextFlightEntry? {
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
            
            var pastFlights: [NextFlightEntry] = []
            var upcomingFlights: [NextFlightEntry] = []
            
            // 워크타입(Fly/TVL) 필터 적용 항공편 계산
            for (_, flights) in schedules {
                for flight in flights {
                    guard let workType = flight["WorkType"],
                          (workType == "FLY" || workType == "TVL") else { continue }
                    
                    guard let depTimeStr = flight["DepStnTime"],
                          let depDateStr = flight["DepDate"],
                          let departureDate = formatter.date(from: "\(depDateStr) \(depTimeStr)") else { continue }
                    
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
                        previousFlightNumber: nil,
                        previousDeparture: nil,
                        previousArrival: nil,
                        previousDepartureDate: nil,
                        previousDepStnTime: nil,
                        previousArrStnTime: nil,
                        previousItem: nil,
                        nextFlightNumber: nil,
                        nextDeparture: nil,
                        nextArrival: nil,
                        nextDepartureDate: nil,
                        nextDepStnTime: nil,
                        nextArrStnTime: nil,
                        nextItem: nil,
                        otherFlights: nil
                    )
                    
                    if departureDate <= now {
                        pastFlights.append(entry)
                    } else {
                        upcomingFlights.append(entry)
                    }
                }
            }
            
            pastFlights.sort { $0.departureDate > $1.departureDate }
            upcomingFlights.sort { $0.departureDate < $1.departureDate }
            
            guard let currentFlight = upcomingFlights.first else {
                return nil
            }
            
            let previousFlight = pastFlights.first
            let nextFlight = upcomingFlights.count > 1 ? upcomingFlights[1] : nil
            
            // loadAllSKD() 함수를 사용하여 모든 스케줄 중 오늘 이후 출발하는 항목만 필터링하고,
            // 상위 3개 항목 추출
            let allFlights = loadAllSKD().filter { $0.departureDate > now }
            let threeFlights = Array(allFlights.prefix(3))
            
            let combinedEntry = NextFlightEntry(
                date: now,
                flightNumber: currentFlight.flightNumber,
                departure: currentFlight.departure,
                arrival: currentFlight.arrival,
                departureDate: currentFlight.departureDate,
                remainingTime: currentFlight.remainingTime,
                depStnTime: currentFlight.depStnTime,
                arrStnTime: currentFlight.arrStnTime,
                item: currentFlight.item,
                dutyReport: currentFlight.dutyReport,
                previousFlightNumber: previousFlight?.flightNumber,
                previousDeparture: previousFlight?.departure,
                previousArrival: previousFlight?.arrival,
                previousDepartureDate: previousFlight?.departureDate,
                previousDepStnTime: previousFlight?.depStnTime,
                previousArrStnTime: previousFlight?.arrStnTime,
                previousItem: previousFlight?.item,
                nextFlightNumber: nextFlight?.flightNumber,
                nextDeparture: nextFlight?.departure,
                nextArrival: nextFlight?.arrival,
                nextDepartureDate: nextFlight?.departureDate,
                nextDepStnTime: nextFlight?.depStnTime,
                nextArrStnTime: nextFlight?.arrStnTime,
                nextItem: nextFlight?.item,
                otherFlights: threeFlights
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
        .caption.bold()
    }
    
    var itemFont: Font {
        let captionSize = UIFont.preferredFont(forTextStyle: .caption1).pointSize * fontMultiplier
        return .system(size: captionSize)
    }
    
    var mainTitleFont: Font {
        let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 1.2 * fontMultiplier
        return .system(size: baseSize, weight: .bold)
    }
    
    // airportTimeFont: systemLarge와 달리 미디엄/스몰은 기본값 사용
    var airportTimeFont: Font {
        if widgetFamily == .systemLarge {
            let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 1.2 * fontMultiplier * 1.2
            return .system(size: baseSize, weight: .bold)
        } else {
            let baseSize = UIFont.preferredFont(forTextStyle: .title1).pointSize * 0.6 * fontMultiplier
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
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let now = context.date
            let remaining = entry.departureDate.timeIntervalSince(now)
            
            ZStack {
                Color.clear.ignoresSafeArea()
                
                if widgetFamily == .systemMedium {
                    // 미디움 위젯: 왼쪽 셀은 기존 스몰 위젯 모양 그대로,
                    // 오른쪽 셀은 loadAllSKD()로 가져온 오늘 이후 상위 3개 스케줄을 "날짜 + 줄바꿈 + 세부사항" 형태로 표시
                    HStack(spacing: 0) {
                        // 왼쪽: 기존 스몰 위젯 내용
                        VStack(spacing: 2) {
                            Text(formatDate(entry.departureDate))
                                .font(dateFont)
                                .bold()
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            
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
                                    .font(.title2)
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
                                            .padding(.horizontal, 8)
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
                                        .padding(.horizontal, 8)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundColor(colorScheme == .dark ? .white : .blue)
                                        .clipShape(Capsule())
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .padding(0)
                        .frame(maxWidth: .infinity)
                        
                        // Divider에 좌우 간격 추가
                        Divider()
                            .padding(.horizontal, 8)
                        
                        // 오른쪽: 저장된 모든 스케줄 중 오늘 이후 상위 3개 항목 표시 (날짜 + 줄바꿈 + 세부사항)
                        VStack(alignment: .leading, spacing: 4) {
                            if let flights = entry.otherFlights, !flights.isEmpty {
                                ForEach(flights.indices, id: \.self) { index in
                                    let flight = flights[index]
                                    
                                    // FLY/TVL 여부 판별
                                    let isFlight = (flight.workType == "FLY" || flight.workType == "TVL")
                                    
                                    // 진한 색상 (바/글씨)와 연한 배경색 지정
                                    let barColor: Color = isFlight ? .blue : .red
                                    let backgroundColor: Color = barColor.opacity(0.2)
                                    
                                    HStack(spacing: 8) {
                                        // 왼쪽 세로 바
                                        Rectangle()
                                            .fill(barColor)
                                            .frame(width: 4)
                                        
                                        // 텍스트 영역
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(formatDate(flight.departureDate))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            Text(flight.detailText())
                                                .font(.caption)
                                                .bold()
                                                .foregroundColor(barColor)
                                        }
                                        
                                        // Spacer를 추가해 전체 행을 채움
                                        Spacer()
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity)   // 전체 너비로 확장
                                    .background(backgroundColor)  // 전체 행 배경 적용
                                    .cornerRadius(6)
                                    
                                    // 항목 사이 Divider
                                    if index < flights.count - 1 {
                                        Divider()
                                    }
                                }
                            } else {
                                Text("No Schedules")
                                    .font(.caption)
                            }
                        }
                        .padding(0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if widgetFamily == .systemLarge {
                    // 기존 systemLarge 모양 그대로
                    VStack(spacing: 2) {
                        Text(formatDate(entry.departureDate))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
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
                                .font(.title2)
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
                                        .padding(.horizontal, 8)
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
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(colorScheme == .dark ? .white : .blue)
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        
                        if entry.previousDepartureDate != nil || entry.nextDepartureDate != nil {
                            Divider()
                            HStack {
                                if let previousDate = entry.previousDepartureDate {
                                    VStack(spacing: 2) {
                                        Text("Previous FLT")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(formatDate(previousDate))
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                        if let previousItem = entry.previousItem, !previousItem.isEmpty {
                                            Text(previousItem)
                                                .font(.caption)
                                                .bold()
                                                .foregroundColor(.blue)
                                                .multilineTextAlignment(.center)
                                        }
                                        HStack {
                                            VStack(spacing: 1) {
                                                Text(entry.previousDeparture ?? "N/A")
                                                    .font(.headline)
                                                    .bold()
                                                    .multilineTextAlignment(.center)
                                                Text(entry.previousDepStnTime ?? "--:--")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .multilineTextAlignment(.center)
                                            }
                                            Image(systemName: "airplane")
                                                .foregroundColor(.blue)
                                            VStack(spacing: 1) {
                                                Text(entry.previousArrival ?? "N/A")
                                                    .font(.headline)
                                                    .bold()
                                                    .multilineTextAlignment(.center)
                                                Text(entry.previousArrStnTime ?? "--:--")
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
                                
                                if let nextDate = entry.nextDepartureDate {
                                    VStack(spacing: 2) {
                                        Text("Next FLT")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(formatDate(nextDate))
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                        if let nextItem = entry.nextItem, !nextItem.isEmpty {
                                            Text(nextItem)
                                                .font(.caption)
                                                .bold()
                                                .foregroundColor(.blue)
                                                .multilineTextAlignment(.center)
                                        }
                                        HStack {
                                            VStack(spacing: 1) {
                                                Text(entry.nextDeparture ?? "N/A")
                                                    .font(.headline)
                                                    .bold()
                                                    .multilineTextAlignment(.center)
                                                Text(entry.nextDepStnTime ?? "--:--")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .multilineTextAlignment(.center)
                                            }
                                            Image(systemName: "airplane")
                                                .foregroundColor(.blue)
                                            VStack(spacing: 1) {
                                                Text(entry.nextArrival ?? "N/A")
                                                    .font(.headline)
                                                    .bold()
                                                    .multilineTextAlignment(.center)
                                                Text(entry.nextArrStnTime ?? "--:--")
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
                } else {
                    // 스몰 위젯: 기존 모양 그대로
                    VStack(spacing: 2) {
                        Text(formatDate(entry.departureDate))
                            .font(dateFont)
                            .bold()
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
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
                                    .minimumScaleFactor(0.4)
                                Text(entry.depStnTime ?? "--:--")
                                    .font(airportTimeFont)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            Spacer()
                            Image(systemName: "airplane")
                                .foregroundColor(.blue)
                                .font(.title2)
                            Spacer()
                            VStack(alignment: .center, spacing: 1) {
                                Text(entry.arrival)
                                    .font(mainTitleFont)
                                    .bold()
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.4)
                                Text(entry.arrStnTime ?? "--:--")
                                    .font(airportTimeFont)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                        
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
                                        .padding(.horizontal, 8)
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
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(colorScheme == .dark ? .white : .blue)
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(0)
                }
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
        .description("Displays current, previous and next flight details with real-time countdown. The medium widget is split horizontally with the left column showing the small widget view and the right column showing 3 upcoming schedules (all work types) separated by dividers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
