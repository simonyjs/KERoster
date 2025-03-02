//
//  KERosterWidget.swift
//  KERosterWidget
//
//  Created by 윤정섭 on 2025/03/02.
//

import WidgetKit
import SwiftUI

// 데이터 모델: 항공편 스케줄
struct FlightScheduleEntry: TimelineEntry {
    let date: Date
    let flightNumber: String
    let departure: String
    let arrival: String
    let departureTime: String
    let arrivalTime: String
}

// 타임라인 제공자: 실제 데이터 로직은 필요에 따라 수정
struct FlightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlightScheduleEntry {
        FlightScheduleEntry(date: Date(), flightNumber: "KE123", departure: "ICN", arrival: "JFK", departureTime: "10:00", arrivalTime: "14:00")
    }
    
    func getSnapshot(in context: Context, completion: @escaping (FlightScheduleEntry) -> Void) {
        let entry = FlightScheduleEntry(date: Date(), flightNumber: "KE123", departure: "ICN", arrival: "JFK", departureTime: "10:00", arrivalTime: "14:00")
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<FlightScheduleEntry>) -> Void) {
        let flightEntry = FlightScheduleEntry(
            date: Date(),
            flightNumber: "KE987",
            departure: "ICN",
            arrival: "LAX",
            departureTime: "15:30",
            arrivalTime: "22:45"
        )
        
        // 1시간 후에 업데이트
        let timeline = Timeline(entries: [flightEntry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
}

// SwiftUI 기반 위젯 UI
struct KERosterWidgetEntryView: View {
    var entry: FlightTimelineProvider.Entry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Flight")
                .font(.headline)
                .foregroundColor(.blue)
            
            Text("\(entry.flightNumber)")
                .font(.title3)
                .bold()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("✈️ \(entry.departure) → \(entry.arrival)")
                        .font(.subheadline)
                    Text("🕑 \(entry.departureTime) - \(entry.arrivalTime)")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color.white)
        .containerBackground(.fill, for: .widget)
    }
}

