//
//  ScheduleDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/31.
//

import UIKit

class ScheduleDetailViewController: UIViewController {
    
    var scheduleDetails: [String: String] = [:] // 선택된 날짜의 스케줄 정보
    var selectedDate: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Schedule Details"
        view.backgroundColor = .white
        
        setupUI() // UI 요소 설정
    }
    
    func setupUI() {
        let dateLabel = createLabel(text: "📅 날짜: \(selectedDate)", fontSize: 20, isBold: true)
        let activityLabel = createLabel(text: "✈️ 활동: \(scheduleDetails["Activity"] ?? "없음")")
        let workTypeLabel = createLabel(text: "💼 근무 유형: \(scheduleDetails["WorkType"] ?? "없음")")
        let itemLabel = createLabel(text: "🛫 항공편: \(scheduleDetails["Item"] ?? "없음")")
        let depLabel = createLabel(text: "📍 출발지: \(scheduleDetails["DepAp"] ?? "없음") | \(scheduleDetails["DepStnTime"] ?? "없음")")
        let arrLabel = createLabel(text: "📍 도착지: \(scheduleDetails["ArrAp"] ?? "없음") | \(scheduleDetails["ArrStnTime"] ?? "없음")")
        let flyingHoursLabel = createLabel(text: "⏳ 비행 시간: \(scheduleDetails["FlyingHours"] ?? "없음")")
        let dutyHoursLabel = createLabel(text: "⌛ 근무 시간: \(scheduleDetails["DutyHours"] ?? "없음")")
        
        let stackView = UIStackView(arrangedSubviews: [dateLabel, activityLabel, workTypeLabel, itemLabel, depLabel, arrLabel, flyingHoursLabel, dutyHoursLabel])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
    }
    
    func createLabel(text: String, fontSize: CGFloat = 16, isBold: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = isBold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
