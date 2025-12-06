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
        
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0   // 섹션 헤더 위쪽 기본 패딩 제거
        }
        tableView.separatorStyle = .none   // ← 검은색 기본 separator 제거
        
        // 새로고침 컨트롤 설정 (Pull-to-Refresh)
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
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
        
        // 연도 및 월을 날짜순으로 정렬 (최근 연도 우선)
        sortedYears = yearMonthSchedules.keys.sorted { y1, y2 in
            // "Unknown"은 항상 맨 아래로 보내기
            if y1 == "Unknown" { return false }
            if y2 == "Unknown" { return true }
            // 숫자/문자 비교 모두 "큰 연도"가 위로 오도록
            return y1 > y2
        }

        for year in sortedYears {
            sortedMonthsByYear[year] = yearMonthSchedules[year]?.keys.sorted { (month1, month2) -> Bool in
                if let date1 = monthFormatter.date(from: month1), let date2 = monthFormatter.date(from: month2) {
                    return date1 > date2
                }
                return month1 < month2
            }
        }
    }
    
    // MARK: - Year Aggregation Helper

    /// 특정 연도의 전체 FLY 횟수 / 비행시간 / 듀티시간 합산
    private func aggregateYearTotals(for year: String) -> (flightCount: Int, flyingHours: Double, dutyHours: Double) {
        guard let months = yearMonthSchedules[year] else {
            return (0, 0.0, 0.0)
        }
        
        var totalFLYCount = 0
        var totalFlyingHours = 0.0
        var totalDutyHours = 0.0
        
        for (_, schedulesInMonth) in months {
            for schedule in schedulesInMonth {
                if schedule["WorkType"] == "FLY" {
                    totalFLYCount += 1
                    if let fhString = schedule["FlyingHours"],
                       let fh = convertTimeStringToHours(fhString) {
                        totalFlyingHours += fh
                    }
                }
                if let dhString = schedule["DutyHours"],
                   let dh = convertTimeStringToHours(dhString) {
                    totalDutyHours += dh
                }
            }
        }
        
        return (totalFLYCount, totalFlyingHours, totalDutyHours)
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
        
        let year = sortedYears[section]
        
        let yearLabel = UILabel()
        yearLabel.translatesAutoresizingMaskIntoConstraints = false
        yearLabel.font = UIFont.boldSystemFont(ofSize: 24)
        yearLabel.text = year
        yearLabel.textColor = .black   // 다크/라이트 모드 상관없이 검정
        
        headerView.addSubview(yearLabel)
        
        // "Unknown" 섹션은 합계 표시 생략
        if year != "Unknown" {
            let (flightCount, flyingHours, dutyHours) = aggregateYearTotals(for: year)
            let flyingStr = formatHoursToHHmm(flyingHours)
            let dutyStr = formatHoursToHHmm(dutyHours)
            
            let summaryLabel = UILabel()
            summaryLabel.translatesAutoresizingMaskIntoConstraints = false
            summaryLabel.font = UIFont.systemFont(ofSize: 14)
            summaryLabel.textColor = .darkGray   // 고정된 다크그레이
            summaryLabel.numberOfLines = 1
            summaryLabel.text = "\(flightCount) Flights | \(flyingStr) FH  | \(dutyStr) DH"
            
            headerView.addSubview(summaryLabel)
            
            NSLayoutConstraint.activate([
                yearLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                yearLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 6),
                
                summaryLabel.leadingAnchor.constraint(equalTo: yearLabel.leadingAnchor),
                summaryLabel.topAnchor.constraint(equalTo: yearLabel.bottomAnchor, constant: 2),
                summaryLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -6)
            ])
        } else {
            // Unknown 은 연도만 중앙 정렬 또는 기존 방식
            NSLayoutConstraint.activate([
                yearLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                yearLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
            ])
        }
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 60 // 연도 + 합계 두 줄
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.001 // 섹션 간 간격 없애기
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 56   // 월 높이 조절
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {

        // 중복 멤버 제거
        cell.contentView.subviews.filter { $0.tag == 1001 }.forEach { $0.removeFromSuperview() }

        // 1pt spacing bar (월 셀 간 간격)
        let spacer = UIView(frame: CGRect(x: 0,
                                          y: cell.contentView.bounds.height - 1,
                                          width: cell.contentView.bounds.width,
                                          height: 1))
        spacer.backgroundColor = tableView.backgroundColor ?? .white
        spacer.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        spacer.tag = 1001

        cell.contentView.addSubview(spacer)
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
        let boldFont = UIFont.boldSystemFont(ofSize: 18)
        let regularFont = UIFont.systemFont(ofSize: 12)
        
        // 기존 bar 제거 (중복 방지)
        cell.contentView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }

        // 왼쪽 Bar 생성
        let Bar = UIView(frame: CGRect(x: 3, y: 0, width: 5, height: cell.contentView.bounds.height))
        // 글로벌 색상 정의
        let lightRed = UIColor(red: 0.98, green: 0.68, blue: 0.68, alpha: 1.0)
        Bar.backgroundColor = lightRed
        Bar.autoresizingMask = [.flexibleHeight]
        Bar.tag = 999

        cell.contentView.addSubview(Bar)
        
        let attributedText = NSMutableAttributedString(
            string: "\(month)\n",
            attributes: [
                .font: boldFont,
                .foregroundColor: UIColor.black          // 제목(월) 항상 검정
            ]
        )
        
        let detailsText = """
        \(totalFLYCount) Flight(s)
        \(totalFlyingHoursStr) Flying Hours | \(totalDutyHoursStr) Duty Hours
        """
        
        attributedText.append(NSAttributedString(
            string: detailsText,
            attributes: [
                .font: regularFont,
                .foregroundColor: UIColor.darkGray      // 상세 텍스트 고정 색
            ]))
        
        cell.textLabel?.attributedText = attributedText
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.textColor = .black            // 안전차원에서 기본색도 고정
        
        // 글로벌 색상 정의
        let lightBlue = UIColor(red: 0.88, green: 0.95, blue: 0.98, alpha: 1.0)
        cell.backgroundColor = lightBlue
        
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
    
    /// Double형 시간 값을 "hh+mm" 형식의 문자열로 변환
    private func formatHoursToHHmm(_ hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int(round((hours - Double(wholeHours)) * 60))
        return String(format: "%02d+%02d", wholeHours, minutes)
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
