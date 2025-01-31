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
        let dateLabel = createLabel(text: "📅 DATE: \(selectedDate)", fontSize: 20, isBold: true)

        // ✅ 여러 개의 스케줄을 순차적으로 출력
        let scheduleTexts = scheduleDetailsList.map { details in
            let seq = details["Seq"] ?? "N/A"
            let activity = details["Activity"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let workType = details["WorkType"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let item = details["Item"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let depAp = details["DepAp"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let depDate = details["DepDate"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? selectedDate
            let depTime = details["DepStnTime"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let arrAp = details["ArrAp"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let arrDate = details["ArrDate"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? selectedDate
            let arrTime = details["ArrStnTime"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let flyingHours = details["FlyingHours"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
            let dutyHours = details["DutyHours"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"

            return """
            🔢 NO.: \(seq)
            ✈️ ACTIVITY: \(activity)
            💼 WORK TYPE: \(workType)
            🛫 C/S: \(item)
            📍 DEP: \(depAp) (\(depDate)) - 🕒 STD: \(depTime)
            📍 ARR: \(arrAp) (\(arrDate)) - 🕒 STA: \(arrTime)
            ⏳ FLT TIME: \(flyingHours) ⌛ DUTY HOURS: \(dutyHours)
            """
        }.joined(separator: "\n\n────────────────────────\n\n") // ✅ 가독성을 높이기 위해 구분선 추가

        // ✅ 디버깅: scheduleTexts가 정상적으로 생성되는지 확인
        print("📌 스케줄 상세 내용:\n\(scheduleTexts)")

        let scheduleLabel = createLabel(text: scheduleTexts, fontSize: 16, isBold: false)

        // ✅ UILabel이 들어갈 컨테이너 뷰 추가 (배경색 확인을 위해)
        let containerView = UIView()
        containerView.backgroundColor = .white
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scheduleLabel)

        NSLayoutConstraint.activate([
            scheduleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            scheduleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            scheduleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            scheduleLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10)
        ])

        let stackView = UIStackView(arrangedSubviews: [dateLabel, containerView])
        stackView.axis = .vertical
        stackView.alignment = .fill // ✅ 변경: 텍스트가 잘리는 문제 해결
        stackView.spacing = 15
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
        label.textColor = .black // ✅ 텍스트 색상 추가 (보이지 않는 문제 해결)
        label.numberOfLines = 0 // ✅ 여러 줄 출력 가능하도록 설정
        label.lineBreakMode = .byWordWrapping // ✅ 긴 텍스트가 잘리지 않고 자동 줄바꿈
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
