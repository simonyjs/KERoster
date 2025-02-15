//
//  Airport.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/15.
//

import Foundation

// ApList.json 파일을 위한 공통 Airport 모델 정의
struct Airport: Codable {
    let IATA: String
    let ICAO: String
    let utc_offset: Double  // 표준 시간대 오프셋 (시간 단위)
    let dst: Bool           // 해당 공항이 DST(일광 절약 시간제)를 사용하는지 여부
}

// ApList.json 파일 로딩 함수 (앱 번들 내의 파일을 디코딩)
func loadAirportList() -> [Airport]? {
    guard let path = Bundle.main.path(forResource: "ApList", ofType: "json") else { return nil }
    let url = URL(fileURLWithPath: path)
    do {
        let data = try Data(contentsOf: url)
        let airports = try JSONDecoder().decode([Airport].self, from: data)
        return airports
    } catch {
        print("ApList.json 로딩 실패: \(error)")
        return nil
    }
}

// 공항별 시간대 식별자(TimeZone identifier)를 매핑하는 함수
// 실제 사용 환경에 맞게 IATA 코드와 식별자를 추가/수정하세요.
func timeZoneForAirport(airport: Airport) -> TimeZone? {
    let mapping: [String: String] = [
        "OCA": "America/New_York",
        "CUX": "America/New_York",
        "CSE": "America/New_York",
        "CUS": "America/New_York",
        "JCY": "America/New_York",
        "NUP": "America/New_York",
        "ICY": "America/New_York",
        "KKK": "America/New_York",
        "MHS": "America/New_York",
        "NIR": "America/New_York",
        "GCT": "America/New_York"
        // 필요한 공항 코드에 대해 추가 매핑...
    ]
    
    if let identifier = mapping[airport.IATA] {
        return TimeZone(identifier: identifier)
    }
    return nil
}

// 로컬 시간(날짜+시간 문자열)을 UTC의 시간(HH:mm)으로 변환하는 함수 (정밀한 DST 계산 적용)
// - dateString: "dd-MMM-yyyy" 형식의 날짜 (예: "09-Dec-2024")
// - timeString: "HH:mm" 형식의 시간 (예: "10:21")
// - airportCode: 해당 스케줄의 공항 IATA 코드 (예: "ICN")
// - airports: ApList.json에서 로드한 공항 정보 배열
func convertLocalTimeToUTCTime(dateString: String, timeString: String, airportCode: String, airports: [Airport]) -> String {
    // "dd-MMM-yyyy HH:mm" 형식의 로컬 날짜+시간 문자열 생성
    let localDateTimeString = "\(dateString) \(timeString)"
    let formatter = DateFormatter()
    formatter.dateFormat = "dd-MMM-yyyy HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    
    // 해당 IATA 코드에 해당하는 공항 정보를 검색하여 시간대 설정
    if let airport = airports.first(where: { $0.IATA == airportCode }) {
        // 매핑된 시간대 식별자가 있으면 이를 사용 (DST 규칙 자동 반영)
        if let tz = timeZoneForAirport(airport: airport) {
            formatter.timeZone = tz
        } else {
            // 매핑이 없으면 기존 방식: utc_offset 값과 dst 플래그에 따라 시간대 설정
            let baseOffset = Int(airport.utc_offset * 3600)
            let adjustedOffset = airport.dst ? baseOffset + 3600 : baseOffset
            formatter.timeZone = TimeZone(secondsFromGMT: adjustedOffset)
        }
    } else {
        formatter.timeZone = TimeZone.current
    }
    
    guard let localDate = formatter.date(from: localDateTimeString) else {
        return "N/A"
    }
    
    // 출력 시간대를 UTC로 설정 후 시간(HH:mm)만 반환
    formatter.timeZone = TimeZone(abbreviation: "UTC")
    formatter.dateFormat = "HH:mm"
    let utcTime = formatter.string(from: localDate)
    return utcTime
}

// 각 공항의 오프셋 문자열 반환 (예: "+9", "+8")
func timezoneOffsetString(for airportCode: String, airports: [Airport]) -> String {
    if let airport = airports.first(where: { $0.IATA == airportCode }) {
        let offsetHours = Int(round(airport.utc_offset))
        let sign = offsetHours >= 0 ? "+" : ""
        return "\(sign)\(offsetHours)"
    }
    return "N/A"
}
