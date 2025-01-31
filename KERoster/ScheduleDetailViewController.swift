//
//  ScheduleDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/31.
//

import UIKit

class ScheduleDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    var scheduleDetailsList: [[String: String]] = [] // ✅ 여러 개의 스케줄을 저장하도록 변경
    var selectedDate: String = ""

    let tableView = UITableView() // ✅ 스케줄 리스트를 테이블로 표시

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Schedule Details"
        view.backgroundColor = .white
        
        setupTableView() // ✅ 테이블 뷰 설정
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
        
        let seq = details["Seq"] ?? "N/A"
        let workType = details["WorkType"] ?? "N/A"
        var item = details["Item"] ?? "N/A"
        let depAp = details["DepAp"] ?? "N/A"
        let depDate = details["DepDate"] ?? selectedDate
        let depTime = details["DepStnTime"] ?? "N/A"
        let arrAp = details["ArrAp"] ?? "N/A"
        let arrDate = details["ArrDate"] ?? selectedDate
        let arrTime = details["ArrStnTime"] ?? "N/A"
        let flyingHours = details["FlyingHours"] ?? "N/A"
        let dutyHours = details["DutyHours"] ?? "N/A"

        // ✅ workType이 "FLY"이면 ✈️, "TVL"이면 💺
        var transportIcon = "✈️"
        if workType == "TVL" {
            transportIcon = "💺"
            if !item.isEmpty {
                item = "DH" + item.dropFirst(2) // ✅ 앞 두 글자를 "DH"로 변경
            }
        }

        cell.textLabel?.text = """
        🔢 NO.: \(seq)
        \(transportIcon) \(item)
        📍 DEP: \(depAp) (\(depDate)) - 🕒 STD: \(depTime)
        📍 ARR: \(arrAp) (\(arrDate)) - 🕒 STA: \(arrTime)
        ⏳ FLT TIME: \(flyingHours) ⌛ DUTY HOURS: \(dutyHours)
        """

        cell.textLabel?.numberOfLines = 0
        cell.accessoryType = .detailDisclosureButton // ✅ 수정 버튼 표시
        
        return cell
    }

    // MARK: - UITableViewDelegate
    
    // ✅ 셀을 선택하면 수정 기능 추가
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let details = scheduleDetailsList[indexPath.row]
        showEditAlert(for: details, at: indexPath)
    }
    
    // ✅ 스와이프 삭제 기능 추가
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "삭제") { (_, _, completionHandler) in
            self.scheduleDetailsList.remove(at: indexPath.row) // ✅ 데이터 삭제
            self.tableView.deleteRows(at: [indexPath], with: .fade) // ✅ UI 업데이트
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    // ✅ 스케줄 수정 팝업 표시
    func showEditAlert(for schedule: [String: String], at indexPath: IndexPath) {
        let alert = UIAlertController(title: "EDIT SKD", message: "EDIT FIELD.", preferredStyle: .alert)

        // ✅ 출발 공항 필드
        alert.addTextField { textField in
            textField.text = schedule["DepAp"]
            textField.placeholder = "DEP"
            textField.leftView = self.createLeftLabel(text: "DEP")
            textField.leftViewMode = .always
        }

        // ✅ 도착 공항 필드
        alert.addTextField { textField in
            textField.text = schedule["ArrAp"]
            textField.placeholder = "ARR APO"
            textField.leftView = self.createLeftLabel(text: "ARR")
            textField.leftViewMode = .always
        }

        // ✅ 출발 시간 필드
        alert.addTextField { textField in
            textField.text = schedule["DepStnTime"]
            textField.placeholder = "STD"
            textField.leftView = self.createLeftLabel(text: "STD")
            textField.leftViewMode = .always
        }

        // ✅ 도착 시간 필드
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

    // ✅ 왼쪽 설명 레이블을 생성하는 함수
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
