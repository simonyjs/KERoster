//
//  ScheduleDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/31.
//

import UIKit

class ScheduleDetailViewController: UIViewController {
    
    var scheduleDetailsList: [[String: String]] = [] // ✅ 여러 개의 스케줄을 저장하도록 변경
    var selectedDate: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Schedule Details"
        view.backgroundColor = .white
        
        setupUI() // UI 요소 설정
    }
    
    func setupUI() {
        let dateLabel = createLabel(text: "📅 날짜: \(selectedDate)", fontSize: 20, isBold: true)
        
        // ✅ 여러 개의 스케줄을 순차적으로 출력
        let scheduleTexts = scheduleDetailsList.map { details in
            let seq = details["Seq"] ?? "1"
            let activity = details["Activity"] ?? "없음"
            let workType = details["WorkType"] ?? "없음"
            let item = details["Item"] ?? "없음"
            let depAp = details["DepAp"] ?? "없음"
            let depTime = details["DepStnTime"] ?? "없음"
            let arrAp = details["ArrAp"] ?? "없음"
            let arrTime = details["ArrStnTime"] ?? "없음"
            let flyingHours = details["FlyingHours"] ?? "없음"
            let dutyHours = details["DutyHours"] ?? "없음"
            
            return """
            🔢 순번: \(seq)
            ✈️ 활동: \(activity)
            💼 근무 유형: \(workType)
            🛫 항공편: \(item)
            📍 출발지: \(depAp) | \(depTime)
            📍 도착지: \(arrAp) | \(arrTime)
            ⏳ 비행 시간: \(flyingHours)
            ⌛ 근무 시간: \(dutyHours)
            """
        }.joined(separator: "\n\n")

        let scheduleLabel = createLabel(text: scheduleTexts, fontSize: 16, isBold: false)

        let stackView = UIStackView(arrangedSubviews: [dateLabel, scheduleLabel])
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
