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
    
    // 월별 그룹화: 키는 "MMM yyyy" (예: "Jan 2025"), 값은 해당 달의 모든 스케줄 (날짜별 배열을 플랫하게 합친 것)
    var monthSchedules: [String: [[String: String]]] = [:]
    var sortedMonths: [String] = [] // 날짜순으로 정렬된 월 키 배열

    override func viewDidLoad() {
        super.viewDidLoad()
               
        self.title = "Schedule List by Month"
        view.backgroundColor = .white
        
        // 전달된 schedules 데이터 확인 (디버깅용)
        print("📌 전달된 schedules 데이터: \(schedules)")
        
        // refresh control 추가 (pull-to-refresh)
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        // 그룹화 및 정렬 초기화
        updateMonthSchedules()
        
        // 테이블 뷰 설정
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    @objc func refreshData(_ sender: UIRefreshControl) {
        // 필요에 따라 외부 데이터를 다시 불러오는 로직을 추가할 수 있습니다.
        // 여기서는 schedules 데이터를 기반으로 그룹화와 정렬을 다시 수행합니다.
        updateMonthSchedules()
        tableView.reloadData()
        sender.endRefreshing()
    }
    
    func updateMonthSchedules() {
        // 월별 스케줄과 정렬된 월 배열 초기화
        monthSchedules.removeAll()
        sortedMonths.removeAll()
        
        // 날짜 파싱 및 그룹화를 위한 포맷터 설정
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // schedules의 각 날짜별 스케줄을 월별로 그룹화
        for (dateString, dailySchedules) in schedules {
            if let date = inputFormatter.date(from: dateString) {
                let monthKey = monthFormatter.string(from: date)
                monthSchedules[monthKey, default: []].append(contentsOf: dailySchedules)
            } else {
                monthSchedules["Unknown", default: []].append(contentsOf: dailySchedules)
            }
        }
        
        // 그룹화된 월 키를 Date로 변환하여 날짜순으로 정렬
        let parsedMonths: [(month: String, date: Date)] = monthSchedules.compactMap { (key, _) in
            if let monthDate = monthFormatter.date(from: key) {
                return (month: key, date: monthDate)
            } else {
                return nil
            }
        }
        sortedMonths = parsedMonths.sorted { $0.date < $1.date }.map { $0.month }
    }
    
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedMonths.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let month = sortedMonths[indexPath.row]
        let schedulesInMonth = monthSchedules[month] ?? []
        
        // 총계 산출 변수들
        var totalFLYCount = 0
        var totalFlyingHours = 0.0
        var totalDutyHours = 0.0
        
        // 각 스케줄을 순회하며 값 합산
        for schedule in schedulesInMonth {
            let workType = schedule["WorkType"] ?? ""
            if workType == "FLY" {
                totalFLYCount += 1
                if let fhString = schedule["FlyingHours"] {
                    let trimmed = fhString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let fh = convertTimeStringToHours(trimmed) {
                        totalFlyingHours += fh
                    } else {
                        print("Conversion failed for FLY FlyingHours: \(trimmed)")
                    }
                }
            }
            // DutyHours는 모든 스케줄(FLY, TVL 등)에서 합산
            if let dhString = schedule["DutyHours"] {
                let trimmed = dhString.trimmingCharacters(in: .whitespacesAndNewlines)
                if let dh = convertTimeStringToHours(trimmed) {
                    totalDutyHours += dh
                } else {
                    print("Conversion failed for DutyHours: \(trimmed)")
                }
            }
        }
        
        // 누적된 시간을 "hh:mm" 형식으로 변환
        let totalFlyingHoursStr = formatHoursToHHmm(totalFlyingHours)
        let totalDutyHoursStr = formatHoursToHHmm(totalDutyHours)
        
        // ✅ NSAttributedString을 사용하여 월을 굵게 표시
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
        
        let selectedMonth = sortedMonths[indexPath.row]
        let details = monthSchedules[selectedMonth] ?? []
        
        // 상세보기 컨트롤러로 해당 달의 스케줄 배열과 달 정보를 전달합니다.
        let detailVC = ScheduleDetailViewController()
        detailVC.scheduleDetailsList = details
        detailVC.selectedDate = selectedMonth
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    // MARK: - Helper Functions
    
    /// 입력된 시간 문자열을 Double 값(시간 단위)으로 변환합니다.
    /// - 만약 문자열이 "HH:mm" 형식이면, 시와 분을 분리하여 소수점 시간으로 계산합니다.
    /// - 그렇지 않으면 일반적인 Double 변환을 시도합니다.
    private func convertTimeStringToHours(_ timeString: String) -> Double? {
        let trimmed = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            if parts.count == 2,
               let hours = Double(parts[0]),
               let minutes = Double(parts[1]) {
                return hours + minutes / 60.0
            }
            return nil
        } else {
            return Double(trimmed)
        }
    }
    
    /// Double 값(시간)을 "hh:mm" 형식의 문자열로 변환합니다.
    private func formatHoursToHHmm(_ hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int(round((hours - Double(wholeHours)) * 60))
        return String(format: "%02d:%02d", wholeHours, minutes)
    }
}
