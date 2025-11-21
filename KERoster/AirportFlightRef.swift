//
//  AirportFlightRef.swift
//  KERoster
//
//  Created by 윤정섭 on 11/21/25.
//

import Foundation

/// 공항별로 묶어서 보여줄 때, 어느 날짜/몇 번째 엔트리인지까지 포함한 참조
struct AirportFlightRef {
    let dateKey: String      // "dd-MMM-yyyy" (schedules 딕셔너리 키)
    let indexInDay: Int      // 해당 날짜 배열에서의 index
    let entry: [String:String]
}
