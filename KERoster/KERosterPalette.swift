//
//  KERosterPalette.swift
//  KERoster
//
//  Created by 윤정섭 on 12/7/25.
//

import UIKit

enum KERosterPalette {
    /// 메인 포인트 컬러 (위젯에서 쓰는 파란색 계열)
    static let primary = UIColor.systemBlue
    /// 메인 포인트의 연한 배경 (Color.blue.opacity(0.15) 느낌)
    static let primaryBackground = UIColor.systemBlue.withAlphaComponent(0.15)

    /// 섹션 헤더 배경 (살짝 더 연한 블루 톤)
    static let headerBackground = UIColor.systemBlue.withAlphaComponent(0.08)
    /// 섹션 헤더 라인 색
    static let headerHairline = UIColor.systemBlue.withAlphaComponent(0.3)

    /// 전체 배경색 (테이블/뷰 기본 배경)
    static let tableBackground = UIColor.systemBackground

    /// 텍스트
    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel

    /// 인덱스 바 색
    static let sectionIndex = UIColor.systemBlue
    static let sectionIndexTracking = UIColor.systemBlue.withAlphaComponent(0.15)

    /// 데이터 없음 표시 라벨 컬러
    static let emptyLabel = UIColor.secondaryLabel
}
