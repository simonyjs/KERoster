//
//  KERosterWidgetLiveActivity.swift
//  KERosterWidget
//
//  Created by 윤정섭 on 2025/03/02.
//

import ActivityKit
import WidgetKit
import SwiftUI

// Live Activity 관련 속성 정의
struct KERosterWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var emoji: String
    }
    var name: String
}

// Live Activity 위젯 정의 (개별 위젯에는 @main을 사용하지 않습니다)
struct KERosterWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KERosterWidgetAttributes.self) { context in
            // 잠금 화면/배너 UI
            VStack {
                Text("Live Activity: \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.blue)
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
        }
    }
}
