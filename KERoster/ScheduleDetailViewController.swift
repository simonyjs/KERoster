//
//  ScheduleDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/31.
//

import UIKit

// ScheduleEditDelegate는 편집/삭제 후 데이터를 전달하기 위한 프로토콜로 가정합니다.
protocol ScheduleEditDelegate: AnyObject {
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int)
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int)
}

class ScheduleDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, ScheduleEditDelegate {
    
    // 여러 개의 스케줄을 저장 (월별 그룹일 경우, 여러 날짜의 스케줄이 플랫하게 합쳐짐)
    var scheduleDetailsList: [[String: String]] = []
    // ViewListViewController에서 전달받은 날짜 또는 달 문자열
    // (예: "Mar 2025" – 글로벌 스케줄은 UserDefaults에 [String: [[String: String]]] 형식으로 "dd-MMM-yyyy" 키를 사용)
    var selectedDate: String = ""
    
    let tableView = UITableView() // 스케줄 리스트를 테이블로 표시
    
    // UserDefaults에 저장된 글로벌 스케줄 데이터를 위한 key (다른 ViewController와 동일)
    let schedulesUserDefaultsKey = "schedules"
    
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
    
    // MARK: - 테이블뷰 설정
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
    
    /// 스케줄들을 DepDate 기준으로 오름차순 정렬
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
    
    // 스와이프하여 삭제 액션 구현 (삭제 후 글로벌 스케줄 업데이트 호출)
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "삭제") { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            print("삭제 액션 호출 - index: \(indexPath.row)")
            self.scheduleDetailsList.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            self.updateGlobalSchedulesFromDetails()
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    // MARK: - ScheduleEditDelegate
    
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int) {
        scheduleDetailsList[index] = schedule
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        updateGlobalSchedulesFromDetails()
    }
    
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int) {
        scheduleDetailsList.remove(at: index)
        tableView.reloadData()
        updateGlobalSchedulesFromDetails()
    }
    
    // MARK: - 글로벌 스케줄 업데이트 (UserDefaults)
    /// ScheduleDetailViewController에서 편집/삭제된 스케줄들을 UserDefaults에 저장된 글로벌 스케줄 데이터와 동기화합니다.
    /// - 전제: 글로벌 스케줄 데이터는 [String: [[String: String]]] 형식이며, 각 키는 "dd-MMM-yyyy" 형식의 날짜 문자열입니다.
    func updateGlobalSchedulesFromDetails() {
        // 만약 selectedDate가 비어있다면 업데이트하지 않습니다.
        guard !selectedDate.isEmpty else { return }
        
        // 글로벌 스케줄 로드
        var globalSchedules: [String: [[String: String]]] = [:]
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                globalSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            } catch {
                print("ScheduleDetailViewController: 글로벌 스케줄 로드 실패: \(error)")
            }
        }
        
        // 현재 화면에 표시된 스케줄들을 DepDate 기준으로 그룹화
        var updatedGroup: [String: [[String: String]]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        for schedule in scheduleDetailsList {
            if let depDate = schedule["DepDate"] {
                updatedGroup[depDate, default: []].append(schedule)
            }
        }
        
        // "MMM yyyy" 형식의 포맷터 (selectedDate와 비교)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let selectedMonth = selectedDate  // 예: "Mar 2025"
        
        // 글로벌 스케줄 중에서 선택된 월에 해당하는 날짜 키들만 업데이트
        for key in globalSchedules.keys {
            if let date = dateFormatter.date(from: key) {
                let keyMonth = monthFormatter.string(from: date)
                if keyMonth == selectedMonth {
                    // 만약 updatedGroup에 해당 key가 있다면 업데이트, 없으면 해당 key 제거
                    if let newValue = updatedGroup[key] {
                        globalSchedules[key] = newValue
                        updatedGroup.removeValue(forKey: key)
                    } else {
                        globalSchedules.removeValue(forKey: key)
                    }
                }
            }
        }
        
        // updatedGroup에 남은 키들(선택된 월에 해당하는 새로운 날짜들)을 추가
        for (key, value) in updatedGroup {
            if let date = dateFormatter.date(from: key) {
                let keyMonth = monthFormatter.string(from: date)
                if keyMonth == selectedMonth {
                    globalSchedules[key] = value
                }
            }
        }
        
        // 업데이트된 글로벌 스케줄 저장
        do {
            let data = try JSONEncoder().encode(globalSchedules)
            UserDefaults.standard.set(data, forKey: schedulesUserDefaultsKey)
            print("ScheduleDetailViewController: 글로벌 스케줄 저장 성공")
        } catch {
            print("ScheduleDetailViewController: 글로벌 스케줄 저장 실패: \(error)")
        }
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
