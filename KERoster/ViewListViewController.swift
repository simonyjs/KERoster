//
//  ViewListViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/30.
//

import UIKit

class ViewListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    @IBOutlet weak var tableView: UITableView! // 스토리보드에 연결한 테이블뷰
    
    // 날짜별 스케줄 (키: "22-Jan-2025", 값: 해당 날짜의 스케줄 배열)
    var schedules: [String: [[String: String]]] = [:]
    
    // 연도 및 월별로 그룹화된 스케줄 데이터 구조
    var yearMonthSchedules: [String: [String: [[String: String]]]] = [:]
    var sortedYears: [String] = [] // 정렬된 연도 배열
    var sortedMonthsByYear: [String: [String]] = [:] // 연도별로 정렬된 월 배열
    
    // UserDefaults에 저장된 schedules 데이터를 불러올 때 사용할 key
    let schedulesUserDefaultsKey = "schedules"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Schedule List By Month(Year)"
        view.backgroundColor = .white
        
        // 새로고침 컨트롤 설정 (Pull-to-Refresh)
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        // 만약 schedules가 외부에서 전달되지 않았다면, 영구 저장소에서 불러옵니다.
//        if schedules.isEmpty {
//            loadSchedules()
//        }
        // iCloud KVS → App Group 폴백
        NSUbiquitousKeyValueStore.default.synchronize()
        if let json = NSUbiquitousKeyValueStore.default.string(forKey: "schedules_json"),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
            schedules = decoded
        } else if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
                  let data = sharedDefaults.data(forKey: schedulesUserDefaultsKey),
                  let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
            schedules = decoded
        } else {
            schedules = [:]
        }
        
        // 스케줄 데이터를 연도 및 월별로 그룹화
        updateYearMonthSchedules()
        
        // 테이블 뷰 설정
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    // 화면이 다시 나타날 때마다 최신 데이터를 불러와 갱신합니다.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSchedules()
        updateYearMonthSchedules()
        tableView.reloadData()
    }
    
    // MARK: - 데이터 새로고침
    
    @objc func refreshData(_ sender: UIRefreshControl) {
        updateYearMonthSchedules()
        tableView.reloadData()
        sender.endRefreshing()
    }
    
    // MARK: - 스케줄 그룹화
    
    /// schedules 딕셔너리에 저장된 날짜별 스케줄을 연도 및 월별로 그룹화
    func updateYearMonthSchedules() {
        yearMonthSchedules.removeAll()
        sortedYears.removeAll()
        sortedMonthsByYear.removeAll()
        
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        
        // 날짜별 스케줄을 연도 및 월별로 그룹화
        for (dateString, dailySchedules) in schedules {
            if let date = inputFormatter.date(from: dateString) {
                let yearKey = yearFormatter.string(from: date)
                let monthKey = monthFormatter.string(from: date)
                yearMonthSchedules[yearKey, default: [:]][monthKey, default: []].append(contentsOf: dailySchedules)
            } else {
                // 날짜 파싱에 실패한 경우 "Unknown" 그룹에 할당
                yearMonthSchedules["Unknown", default: [:]]["Unknown", default: []].append(contentsOf: dailySchedules)
            }
        }
        
        // 연도 및 월을 날짜순으로 정렬
        sortedYears = yearMonthSchedules.keys.sorted()
        for year in sortedYears {
            sortedMonthsByYear[year] = yearMonthSchedules[year]?.keys.sorted { (month1, month2) -> Bool in
                if let date1 = monthFormatter.date(from: month1), let date2 = monthFormatter.date(from: month2) {
                    return date1 < date2
                }
                return month1 < month2
            }
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sortedYears.count // 섹션 수는 연도의 수와 동일
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let year = sortedYears[section]
        return sortedMonthsByYear[year]?.count ?? 0 // 각 섹션(연도)별 월의 개수 반환
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil // 커스텀 헤더를 사용하기 위해 nil 반환
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = .systemGray6
        
        let yearLabel = UILabel()
        yearLabel.translatesAutoresizingMaskIntoConstraints = false
        yearLabel.font = UIFont.boldSystemFont(ofSize: 30)
        yearLabel.text = sortedYears[section]
        
        headerView.addSubview(yearLabel)
        
        NSLayoutConstraint.activate([
            yearLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            yearLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 50 // 헤더 높이 설정
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let year = sortedYears[indexPath.section]
        let month = sortedMonthsByYear[year]?[indexPath.row] ?? ""
        let schedulesInMonth = yearMonthSchedules[year]?[month] ?? []
        
        // 총계 산출 변수들
        var totalFLYCount = 0
        var totalFlyingHours = 0.0
        var totalDutyHours = 0.0
        
        // 해당 월의 모든 스케줄을 순회하며 합산
        for schedule in schedulesInMonth {
            if schedule["WorkType"] == "FLY" {
                totalFLYCount += 1
                if let fhString = schedule["FlyingHours"], let fh = convertTimeStringToHours(fhString) {
                    totalFlyingHours += fh
                }
            }
            if let dhString = schedule["DutyHours"], let dh = convertTimeStringToHours(dhString) {
                totalDutyHours += dh
            }
        }
        
        // 누적된 시간을 "hh:mm" 형식으로 변환
        let totalFlyingHoursStr = formatHoursToHHmm(totalFlyingHours)
        let totalDutyHoursStr = formatHoursToHHmm(totalDutyHours)
        
        // NSAttributedString을 사용하여 월과 상세 정보를 표시
        let boldFont = UIFont.boldSystemFont(ofSize: 20)
        let regularFont = UIFont.systemFont(ofSize: 14)
        
        let attributedText = NSMutableAttributedString(
            string: "🗓️ \(month)\n",
            attributes: [.font: boldFont]
        )
        
        let detailsText = """
        \(totalFLYCount) Flight(s)
        Total Flying Hours = \(totalFlyingHoursStr)
        Total Duty Hours = \(totalDutyHoursStr)
        """
        
        attributedText.append(NSAttributedString(string: detailsText, attributes: [.font: regularFont]))
        
        cell.textLabel?.attributedText = attributedText
        cell.textLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let year = sortedYears[indexPath.section]
        let month = sortedMonthsByYear[year]?[indexPath.row] ?? ""
        let details = yearMonthSchedules[year]?[month] ?? []
        
        // 상세보기 화면으로 이동 (ScheduleDetailViewController는 별도 구현)
        let detailVC = ScheduleDetailViewController()
        detailVC.scheduleDetailsList = details
        detailVC.selectedDate = month // 선택된 월(또는 날짜) 정보를 전달
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    // MARK: - Helper Functions
    
    /// 시간 문자열(예: "02:50")을 Double형 시간(예: 2.83)으로 변환
    private func convertTimeStringToHours(_ timeString: String) -> Double? {
        let trimmed = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            if parts.count == 2, let hours = Double(parts[0]), let minutes = Double(parts[1]) {
                return hours + minutes / 60.0
            }
        }
        return Double(trimmed)
    }
    
    /// Double형 시간 값을 "hh:mm" 형식의 문자열로 변환
    private func formatHoursToHHmm(_ hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int(round((hours - Double(wholeHours)) * 60))
        return String(format: "%02d:%02d", wholeHours, minutes)
    }
    
    // MARK: - 영구 저장소 (UserDefaults) 관련 함수
    
    /// UserDefaults에 저장된 schedules 데이터를 불러옵니다.
    private func loadSchedules() {
        if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
           let data = sharedDefaults.data(forKey: schedulesUserDefaultsKey) {
            do {
                schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
                print("영구 저장소에서 스케줄 데이터를 불러왔습니다.")
            } catch {
                print("스케줄 불러오기 실패: \(error)")
            }
        } else {
            print("영구 저장소에 저장된 스케줄 데이터가 없습니다.")
        }
    }
}
