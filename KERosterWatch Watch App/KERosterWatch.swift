//
//  KERosterWatch.swift
//  KERosterWatch
//
//  Created by 윤정섭 on 2025/04/17.
//

import AppIntents

struct KERosterWatch: AppIntent {
    static var title: LocalizedStringResource = "KERosterWatch"
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
