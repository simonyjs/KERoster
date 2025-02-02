//
//  ScheduleDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/31.
//

import UIKit

class ScheduleDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    // 여러 개의 스케줄을 저장 (월별 그룹일 경우, 여러 날짜의 스케줄이 플랫하게 합쳐짐)
    var scheduleDetailsList: [[String: String]] = []
    // ViewListViewController에서 전달받은 날짜 또는 달 문자열
    var selectedDate: String = ""
    
    let tableView = UITableView() // 스케줄 리스트를 테이블로 표시

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // selectedDate가 전달되었다면 타이틀에 함께 표시 (예: "Schedule Details (Jan 2025)")
        if selectedDate.isEmpty {
            self.title = "Schedule Details"
        } else {
            self.title = "Schedule Details (\(selectedDate))"
        }
        
        view.backgroundColor = .white
        setupTableView() // 테이블 뷰 설정
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 날짜 형식에 맞춰 scheduleDetailsList를 정렬합니다.
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        scheduleDetailsList.sort { (dict1, dict2) -> Bool in
            // 각 스케줄의 DepDate가 없으면 selectedDate를 기본값으로 사용합니다.
            let dateString1 = dict1["DepDate"] ?? selectedDate
            let dateString2 = dict2["DepDate"] ?? selectedDate
            
            if let date1 = dateFormatter.date(from: dateString1),
               let date2 = dateFormatter.date(from: dateString2) {
                return date1 < date2
            }
            // 날짜 변환에 실패하면 문자열 비교
            return dateString1 < dateString2
        }
        
        tableView.reloadData()
    }
    
    func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scheduleDetailsList.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let details = scheduleDetailsList[indexPath.row]
        
        // 날짜 변환을 위한 포맷터 설정
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd"
        
        // DepDate와 ArrDate 원본 문자열 (없으면 selectedDate 사용)
        let depDateOriginal = details["DepDate"] ?? selectedDate
        let arrDateOriginal = details["ArrDate"] ?? selectedDate
        
        // 변환된 날짜 문자열
        let depDateFormatted = inputFormatter.date(from: depDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? depDateOriginal
        let arrDateFormatted = inputFormatter.date(from: arrDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? arrDateOriginal
        
        let workType = details["WorkType"] ?? "N/A"
        
        // workType이 "FLY" 또는 "TVL"인 경우 항공편 관련 정보를 표시
        if workType == "FLY" || workType == "TVL" {
            let seq = details["Seq"] ?? "N/A"
            var item = details["Item"] ?? "N/A"
            let depAp = details["DepAp"] ?? "N/A"
            let depTime = details["DepStnTime"] ?? "N/A"
            let arrAp = details["ArrAp"] ?? "N/A"
            let arrTime = details["ArrStnTime"] ?? "N/A"
            let flyingHours = details["FlyingHours"] ?? "N/A"
            let dutyHours = details["DutyHours"] ?? "N/A"
            
            var transportIcon = ""
            if workType == "FLY" {
                transportIcon = "✈️"
            } else if workType == "TVL" {
                transportIcon = "💺"
                if !item.isEmpty {
                    item = "DH" + item.dropFirst(2)
                }
            }
            
            cell.textLabel?.text = """
            📅 \(depDateFormatted) ~ \(arrDateFormatted)
            \(transportIcon) \(item)
            📍 DEP: \(depAp) - 🕒 STD: \(depTime)
            📍 ARR: \(arrAp) - 🕒 STA: \(arrTime)
            ⏳ FLT TIME: \(flyingHours) ⌛ DUTY HOURS: \(dutyHours)
            """
        }
        // workType이 "FLY" 또는 "TVL"이 아닌 경우 Activity, DutyReport, DutyDebrief 및 날짜 표시
        else {
            let activity = details["Activity"] ?? "N/A"
            let dutyReport = details["DutyReport"] ?? "N/A"
            let dutyDebrief = details["DutyDebrief"] ?? "N/A"
            
            // Activity가 "DO"이면 아이콘을 🏠, 그렇지 않으면 기본 아이콘 🏢
            let icon = (activity == "DO") ? "🏠" : "🏢"
            
            cell.textLabel?.text = """
            📅 \(depDateFormatted)
            \(icon) \(activity)
            \(dutyReport) - \(dutyDebrief)
            """
        }
        
        cell.textLabel?.numberOfLines = 0
        cell.accessoryType = .detailDisclosureButton // 수정 버튼 표시
        
        return cell
    }

    // MARK: - UITableViewDelegate
    
    // 셀의 액세서리 버튼 탭 시 스케줄 수정 팝업 표시
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let details = scheduleDetailsList[indexPath.row]
        showEditAlert(for: details, at: indexPath)
    }
    
    // 스와이프하여 삭제 기능 추가
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "삭제") { (_, _, completionHandler) in
            self.scheduleDetailsList.remove(at: indexPath.row) // 데이터 삭제
            self.tableView.deleteRows(at: [indexPath], with: .fade) // UI 업데이트
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    // 스케줄 수정 팝업 표시
    func showEditAlert(for schedule: [String: String], at indexPath: IndexPath) {
        let alert = UIAlertController(title: "EDIT SKD", message: "EDIT FIELD.", preferredStyle: .alert)

        // 출발 공항 필드
        alert.addTextField { textField in
            textField.text = schedule["DepAp"]
            textField.placeholder = "DEP"
            textField.leftView = self.createLeftLabel(text: "DEP")
            textField.leftViewMode = .always
        }

        // 도착 공항 필드
        alert.addTextField { textField in
            textField.text = schedule["ArrAp"]
            textField.placeholder = "ARR"
            textField.leftView = self.createLeftLabel(text: "ARR")
            textField.leftViewMode = .always
        }

        // 출발 시간 필드
        alert.addTextField { textField in
            textField.text = schedule["DepStnTime"]
            textField.placeholder = "STD"
            textField.leftView = self.createLeftLabel(text: "STD")
            textField.leftViewMode = .always
        }

        // 도착 시간 필드
        alert.addTextField { textField in
            textField.text = schedule["ArrStnTime"]
            textField.placeholder = "STA"
            textField.leftView = self.createLeftLabel(text: "STA")
            textField.leftViewMode = .always
        }

        let saveAction = UIAlertAction(title: "SAVE", style: .default) { _ in
            var updatedSchedule = schedule
            updatedSchedule["DepAp"] = alert.textFields?[0].text
            updatedSchedule["ArrAp"] = alert.textFields?[1].text
            updatedSchedule["DepStnTime"] = alert.textFields?[2].text
            updatedSchedule["ArrStnTime"] = alert.textFields?[3].text

            self.scheduleDetailsList[indexPath.row] = updatedSchedule
            self.tableView.reloadRows(at: [indexPath], with: .automatic)
        }

        let cancelAction = UIAlertAction(title: "CANCEL", style: .cancel, handler: nil)

        alert.addAction(saveAction)
        alert.addAction(cancelAction)

        present(alert, animated: true, completion: nil)
    }

    // 왼쪽에 표시할 설명 레이블 생성 함수
    func createLeftLabel(text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        label.textColor = .darkGray
        label.sizeToFit()

        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: label.frame.width + 10, height: label.frame.height))
        label.frame.origin = CGPoint(x: 5, y: (containerView.frame.height - label.frame.height) / 2)
        containerView.addSubview(label)

        return containerView
    }
}
