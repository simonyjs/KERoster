//
//  KERosterWidgetBundle.swift
//  KERosterWidget
//
//  Created by 윤정섭 on 2025/03/02.
//

import WidgetKit
import SwiftUI

@main
struct KERosterWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextFlightWidget()
        KERosterWidgetLiveActivity() // Live Activity 위젯 (별도 구현된 Live Activity 코드)
    }
}
