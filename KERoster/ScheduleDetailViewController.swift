//
//  ScheduleDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/31.
//

import UIKit

class ScheduleDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, ScheduleEditDelegate {
    
    // 여러 개의 스케줄을 저장 (월별 그룹일 경우, 여러 날짜의 스케줄이 플랫하게 합쳐짐)
    var scheduleDetailsList: [[String: String]] = []
    // ViewListViewController에서 전달받은 날짜 또는 달 문자열
    var selectedDate: String = ""
    
    let tableView = UITableView() // 스케줄 리스트를 테이블로 표시

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if selectedDate.isEmpty {
            self.title = "Schedule Details"
        } else {
            self.title = "Schedule Details (\(selectedDate))"
        }
        
        view.backgroundColor = .white
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sortScheduleDetails()
        tableView.reloadData()
    }
    
    func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        
        // 빈 FooterView 설정하여 불필요한 빈 셀 제거
        tableView.tableFooterView = UIView()
        
        // UIRefreshControl 추가 (당겨서 리로드)
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc func refreshData(_ sender: UIRefreshControl) {
        sortScheduleDetails()
        tableView.reloadData()
        sender.endRefreshing()
    }
    
    func sortScheduleDetails() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        scheduleDetailsList.sort { (dict1, dict2) -> Bool in
            let dateString1 = dict1["DepDate"] ?? selectedDate
            let dateString2 = dict2["DepDate"] ?? selectedDate
            
            if let date1 = dateFormatter.date(from: dateString1),
               let date2 = dateFormatter.date(from: dateString2) {
                return date1 < date2
            }
            return dateString1 < dateString2
        }
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
        
        // 기본 글꼴과 굵은 글꼴
        let defaultFont = UIFont.systemFont(ofSize: 14)
        let boldFont = UIFont.boldSystemFont(ofSize: 20)
        
        // NSAttributedString 구성
        let attributedText = NSMutableAttributedString()
        
        if workType == "FLY" || workType == "TVL" {
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
                transportIcon = "📌"
                if !item.isEmpty {
                    item = "DH" + item.dropFirst(2)
                }
            }
            
            let dateLine: String
            if depDateFormatted == arrDateFormatted {
                dateLine = "📅 \(depDateFormatted)"
            } else {
                dateLine = "📅 \(depDateFormatted) ~ \(arrDateFormatted)"
            }
            attributedText.append(NSAttributedString(string: dateLine, attributes: [.font: defaultFont]))
            
            let flightLine = "\n\(transportIcon) "
            attributedText.append(NSAttributedString(string: flightLine, attributes: [.font: defaultFont]))
            attributedText.append(NSAttributedString(string: item, attributes: [.font: boldFont]))
            
            var detailsLine = "\n📍 \(depTime) \(depAp) - \(arrAp) \(arrTime)\n⏳ FLT TIME: \(flyingHours)\n⌛ DUTY HOURS: \(dutyHours)"
            if let hotel = details["Hotel"], !hotel.isEmpty {
                detailsLine += "\n🏨 Hotel: \(hotel)"
            }
            attributedText.append(NSAttributedString(string: detailsLine, attributes: [.font: defaultFont]))
            
        } else {
            // workType이 "FLY" 또는 "TVL"이 아닐 때
            let activity = details["Activity"] ?? "N/A"
            let dutyReport = details["DutyReport"] ?? "N/A"
            let dutyDebrief = details["DutyDebrief"] ?? "N/A"
            
            // 만약 DutyDebriefDate가 존재하고, DepDate와 다르다면 "DepDate ~ DutyDebriefDate" 형태로 표시
            if let dutyDebriefDateStr = details["DutyDebriefDate"],
               dutyDebriefDateStr != (details["DepDate"] ?? "") {
                let dutyDebriefFormatted = inputFormatter.date(from: dutyDebriefDateStr).flatMap { outputFormatter.string(from: $0) } ?? dutyDebriefDateStr
                attributedText.append(NSAttributedString(string: "📅 \(depDateFormatted) ~ \(dutyDebriefFormatted)\n", attributes: [.font: defaultFont]))
            } else {
                attributedText.append(NSAttributedString(string: "📅 \(depDateFormatted)\n", attributes: [.font: defaultFont]))
            }
            
            let icon = (activity == "DO") ? "🏠" : "🏢"
            let activityPrefix = "\(icon) "
            attributedText.append(NSAttributedString(string: activityPrefix, attributes: [.font: defaultFont]))
            attributedText.append(NSAttributedString(string: activity, attributes: [.font: boldFont]))
            attributedText.append(NSAttributedString(string: " : \(dutyReport) - \(dutyDebrief)", attributes: [.font: defaultFont]))
        }
        
        cell.textLabel?.attributedText = attributedText
        cell.textLabel?.numberOfLines = 0
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let schedule = scheduleDetailsList[indexPath.row]
        let editVC = ScheduleEditViewController()
        editVC.schedule = schedule
        editVC.scheduleIndex = indexPath.row
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "삭제") { (_, _, completionHandler) in
            print("삭제 액션 호출 - index: \(indexPath.row)")
            self.scheduleDetailsList.remove(at: indexPath.row)
            self.tableView.deleteRows(at: [indexPath], with: .fade)
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    // MARK: - ScheduleEditDelegate
    
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int) {
        scheduleDetailsList[index] = schedule
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
    }
    
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int) {
        scheduleDetailsList.remove(at: index)
        tableView.reloadData()
    }
    
    // 왼쪽에 표시할 설명 레이블 생성 함수 (필요시 사용)
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
