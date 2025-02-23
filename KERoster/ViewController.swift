//
//  ViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/22.
//

import UIKit
import WebKit
import SwiftSoup
import Foundation
import EventKit

// SwiftSoup의 Elements 배열에 안전하게 접근 (인덱스 초과 방지)
extension Elements {
    func getOrNil(_ index: Int) -> String {
        return (self.size() > index) ? (try? self.get(index).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" : ""
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    
    @IBOutlet weak var webView: WKWebView!
    @IBOutlet weak var scheduleStackView: UIStackView!
    
    var eventStore: EKEventStore!
    var calendarManager: CalendarManager!
    
    var schedules: [String: [[String: String]]] = [:]
    let schedulesUserDefaultsKey = "schedules"
    let ownerUserDefaultsKey = "ownerInfo"
    let totalHoursByMonthUserDefaultsKey = "totalHoursByMonth"
    var ownerInfo: String = ""
    var totalHours: String = ""
    
    // 저장된 이벤트 수를 추적
    var savedEventCount = 0
    
    // MARK: - 디버그 로그 함수
    func debugLog(_ message: String) {
        print("[DEBUG] \(message)")
    }
    
    // MARK: - 헬퍼 함수: 날짜 포맷 변환 ("yyyy-MM" 포맷)
    func formattedMonth(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    // MARK: - UIViewController LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSchedules()
        
        self.eventStore = EKEventStore()
        self.calendarManager = CalendarManager(eventStore: self.eventStore)
        
        // iOS 17 이상: 캘린더 접근 권한 요청 (Full Access)
        self.eventStore.requestFullAccessToEvents(completion: { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.debugLog("캘린더 접근 권한 승인됨")
                    // 앱 실행 시 캘린더 선택 창을 띄우지 않고,
                    // Export Calendar 버튼에서 선택하도록 변경
                    // self.calendarManager.presentCalendarSelection(from: self) { calendar in
                    //     if let cal = calendar {
                    //         self.debugLog("이벤트 저장할 캘린더: \(cal.title)")
                    //     } else {
                    //         self.debugLog("캘린더 선택이 취소됨")
                    //     }
                    // }
                } else {
                    self.debugLog("캘린더 접근 권한 거부됨: \(error?.localizedDescription ?? "알 수 없는 오류")")
                }
            }
        })
        
        // 네비게이션 바 스타일 설정
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Ocean")
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.isTranslucent = false
        
        printSchedulesToConsole()
        
        // 오른쪽 네비게이션 바 버튼 생성 (스토리보드 연결이 끊어진 경우)
        if navigationItem.rightBarButtonItem == nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.down.fill"),
                style: .plain,
                target: self,
                action: nil
            )
        }
        let importAction = UIAction(title: "Import Schedule", image: UIImage(systemName: "arrow.down.circle")) { _ in
            self.importSchedule()
        }
        // 달력 내보내기 시 최신 데이터를 가져오도록 수정
        let exportAction = UIAction(title: "Export Calendar", image: UIImage(systemName: "arrow.up.circle")) { _ in
            self.loadSchedules() // 최신 스케줄 불러오기
            self.calendarManager.presentCalendarSelection(from: self) { selectedCalendar in
                guard let calendar = selectedCalendar else {
                    self.debugLog("캘린더 선택 취소됨")
                    return
                }
                self.calendarManager.selectedCalendar = calendar
                if let airports = self.loadAirportList() {
                    self.savedEventCount = 0
                    for (_, scheduleEntries) in self.schedules {
                        for entry in scheduleEntries {
                            self.addEventToCalendar(for: entry, airports: airports)
                        }
                    }
                    let calendarName = calendar.title
                    self.showAlert(title: "Calendar export complete", message: "Saved Calendar: \(calendarName)\nTOTAL EVENT NO: \(self.savedEventCount)")
                }
            }
        }

        let menu = UIMenu(title: "Select a task", children: [importAction, exportAction])
        navigationItem.rightBarButtonItem?.menu = menu
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
    }
    
    // MARK: - IBAction
    @IBAction func InputButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let inputCalendarVC = storyboard.instantiateViewController(withIdentifier: "ScheduleInputCalendarViewController") as? ScheduleInputCalendarViewController {
            navigationController?.pushViewController(inputCalendarVC, animated: true)
        }
    }
    
    @IBAction func iflightButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/")
    }
    
    @IBAction func ViewListButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let viewListVC = storyboard.instantiateViewController(withIdentifier: "ViewListViewController") as? ViewListViewController {
            viewListVC.schedules = schedules
            navigationController?.pushViewController(viewListVC, animated: true)
        }
    }
    
    @IBAction func CalendarButtonTapped(_ sender: UIBarButtonItem) {
        debugLog("CalendarButtonTapped 호출됨")
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let calendarVC = storyboard.instantiateViewController(withIdentifier: "MonthlyCalendarViewController") as? MonthlyCalendarViewController {
            calendarVC.schedules = schedules
            calendarVC.ownerInfo = self.ownerInfo
            calendarVC.totalHours = self.totalHours
            navigationController?.pushViewController(calendarVC, animated: true)
        }
    }
    
    @IBAction func infoButtonTapped(_ sender: UIBarButtonItem) {
        if let url = URL(string: "https://pinnate-century-46a.notion.site/KERoster-1973143fe5db80588f62d8959e7c0fcc?pvs=74") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    // 예시: UIButton 액션 - 이벤트 저장 테스트 (새 이벤트 저장)
    @IBAction func saveEventButtonTapped(_ sender: UIButton) {
        calendarManager.presentCalendarSelection(from: self) { selectedCalendar in
            guard let calendar = selectedCalendar else {
                self.debugLog("캘린더 선택 취소됨")
                return
            }
            let event = EKEvent(eventStore: self.eventStore)
            event.title = "예시 이벤트"
            event.startDate = Date().addingTimeInterval(3600)
            event.endDate = event.startDate.addingTimeInterval(3600)
            event.calendar = calendar
            
            self.calendarManager.saveEvent(event: event) { success, error in
                if success {
                    self.debugLog("이벤트 저장 성공: \(String(describing: event.title)) in \(calendar.title)")
                    self.showAlert(title: "Event Saved", message: "\(event.title ?? "Event") \(calendar.title) Saved to your calendar")
                } else {
                    self.debugLog("이벤트 저장 실패: \(error?.localizedDescription ?? "알 수 없음")")
                    self.showAlert(title: "FAILED TO SAVE EVENT", message: error?.localizedDescription ?? "UNKNOWN ERROR")
                }
            }
        }
    }
    
    // MARK: - WebView 관련 메서드
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    
    func loadURL(_ urlString: String) {
        debugLog("loadURL 호출됨: \(urlString)")
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            debugLog("잘못된 URL 형식: \(urlString)")
        }
    }
    
    // MARK: - UserDefaults 관련 (스케줄 저장/불러오기)
    //saveTapped() 실행 시 schedules 데이터가 갱신되지 않거나 UserDefaults에 저장되지 않는 문제
    func saveSchedules() {
        do {
            let data = try JSONEncoder().encode(schedules)
            UserDefaults.standard.set(data, forKey: "schedules")
            UserDefaults.standard.synchronize()
            print("스케줄 저장 성공")
        } catch {
            print("스케줄 저장 실패: \(error)")
        }
    }
    
    func loadSchedules() {
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
                debugLog("스케줄 불러오기 성공")
            } catch {
                debugLog("스케줄 불러오기 실패: \(error)")
            }
        } else {
            debugLog("저장된 스케줄이 없습니다.")
        }
    }
    
    // MARK: - 스케줄 파싱 및 가져오기 (HTML 파싱, SwiftSoup 활용)
    func importSchedule() {
        guard let airports = loadAirportList() else {
            debugLog("ApList.json 로딩 실패")
            DispatchQueue.main.async {
                self.showAlert(title: "Import Fail", message: "Failed to load airport information.")
            }
            return
        }
        debugLog("ApList.json 로드 성공: \(airports.count)개의 공항 정보")
        
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self] (html: Any?, error: Error?) in
            guard let self = self else { return }
            if let error = error {
                self.debugLog("JavaScript 실행 에러: \(error)")
            }
            guard let htmlString = html as? String else {
                self.debugLog("❌ HTML 가져오기 실패")
                DispatchQueue.main.async {
                    self.showAlert(title: "Import failed", message: "Failed to retrieve schedule")
                }
                return
            }
            self.debugLog("HTML 추출 성공")
            
            do {
                let doc: Document = try SwiftSoup.parse(htmlString)
                let rows: Elements = try doc.select("tr")
                var extractedSchedules: [String: [[String: String]]] = [:]
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd-MMM-yyyy"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                
                var lastDate: String = "Unknown"
                var sequenceCounter: [String: Int] = [:]
                let calendar = Calendar.current
                
                func calculateDate(baseDate: String, option: String) -> String {
                    guard let baseDateObj = dateFormatter.date(from: baseDate) else {
                        self.debugLog("날짜 변환 실패: baseDate(\(baseDate))")
                        return baseDate
                    }
                    let pattern = #"([-+]\d+)"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: option, range: NSRange(option.startIndex..., in: option)) {
                        let matchRange = Range(match.range, in: option)!
                        let offsetString = String(option[matchRange]).replacingOccurrences(of: "+", with: "")
                        if let offset = Int(offsetString),
                           let newDate = calendar.date(byAdding: .day, value: offset, to: baseDateObj) {
                            let result = dateFormatter.string(from: newDate)
                            self.debugLog("calculateDate: \(baseDate) \(option) -> \(result)")
                            return result
                        }
                    }
                    return baseDate
                }
                
                func extractDutyDebriefOption(_ dutyDebrief: String) -> String {
                    let pattern = #"\s*\(([-+]\d+)\)\s*$"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: dutyDebrief, range: NSRange(dutyDebrief.startIndex..., in: dutyDebrief)),
                       let range = Range(match.range(at: 1), in: dutyDebrief) {
                        let result = String(dutyDebrief[range])
                        self.debugLog("extractDutyDebriefOption: \(dutyDebrief) -> \(result)")
                        return result
                    }
                    return ""
                }
                
                func extractDutyDebriefTime(_ dutyDebrief: String) -> String {
                    let possibleOpeningParens: [Character] = ["(", "（"]
                    if let index = dutyDebrief.firstIndex(where: { possibleOpeningParens.contains($0) }) {
                        let timePart = dutyDebrief[..<index].trimmingCharacters(in: .whitespaces)
                        let result = String(timePart.prefix(5))
                        self.debugLog("extractDutyDebriefTime: \(dutyDebrief) -> \(result)")
                        return result
                    }
                    let result = String(dutyDebrief.trimmingCharacters(in: .whitespaces).prefix(5))
                    self.debugLog("extractDutyDebriefTime: \(dutyDebrief) -> \(result)")
                    return result
                }
                
                // 소유자 정보 추출
                do {
                    if let ownerElement = try doc.select("body > table > tbody > tr > td:nth-child(2) > table:nth-child(2) > tbody > tr:nth-child(3) > td:nth-child(4) > p > span").first() {
                        let fullOwnerText = try ownerElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if let pipeRange = fullOwnerText.range(of: "|") {
                            self.ownerInfo = String(fullOwnerText[..<pipeRange.lowerBound])
                        } else {
                            self.ownerInfo = fullOwnerText
                        }
                        self.debugLog("소유자 정보 추출 성공: \(self.ownerInfo)")
                    } else {
                        self.debugLog("소유자 정보를 찾을 수 없습니다.")
                    }
                } catch {
                    self.debugLog("소유자 정보 추출 중 오류 발생: \(error)")
                }
                
                // 총 시간 정보 추출
                do {
                    if let hoursElement = try doc.select("body > table > tbody > tr > td:nth-child(2) > table:nth-child(2) > tbody > tr:nth-child(3) > td:nth-child(5) > p > span").first() {
                        self.totalHours = try hoursElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        self.debugLog("총 시간 정보 추출 성공: \(self.totalHours)")
                    } else {
                        self.debugLog("총 시간 정보를 찾을 수 없습니다.")
                    }
                } catch {
                    self.debugLog("총 시간 정보 추출 중 오류 발생: \(error)")
                }
                
                UserDefaults.standard.set(self.ownerInfo, forKey: self.ownerUserDefaultsKey)
                
                var depMonthCount: [String: Int] = [:]
                
                // 스케줄 파싱
                for (_, row) in rows.enumerated() {
                    let columns: Elements = try row.select("td")
                    
                    // 헤더 행은 건너뜁니다.
                    if columns.size() > 10, !(try columns[1].text().contains("Date")) {
                        var missingFields = [String]()
                        
                        var date = columns.getOrNil(1)
                        let activity = columns.getOrNil(2)
                        let dutyReport = columns.getOrNil(3)
                        let item = columns.getOrNil(4)
                        let workType = columns.getOrNil(6)
                        let depStationTimeFull = columns.getOrNil(8)
                        let arrStationTimeFull = columns.getOrNil(9)
                        let dutyDebrief = columns.getOrNil(11)
                        let flyingHours = columns.getOrNil(12)
                        let dutyHours = columns.getOrNil(13)
                        let sdc = columns.getOrNil(14)
                        let hotel = columns.getOrNil(16)
                        
                        // 날짜가 누락되면 이전 날짜 사용, 없으면 로그 후 continue
                        if date.isEmpty {
                            if lastDate == "Unknown" {
                                self.debugLog("날짜 정보 누락: 이전 날짜 정보도 없음")
                                continue
                            }
                            date = lastDate
                        } else {
                            lastDate = date
                        }
                        
                        // 비행 / 그라운드 듀티에 따라 필수 필드 검사
                        if workType == "FLY" || workType == "TVL" {
                            if item.isEmpty { missingFields.append("Item") }
                            if depStationTimeFull.isEmpty { missingFields.append("DepStationTime") }
                            if arrStationTimeFull.isEmpty { missingFields.append("ArrStationTime") }
                            if date.isEmpty { missingFields.append("Date") }
                        } else {
                            if dutyReport.isEmpty { missingFields.append("DutyReport") }
                            if dutyDebrief.isEmpty { missingFields.append("DutyDebrief") }
                            if date.isEmpty { missingFields.append("Date") }
                            if activity.isEmpty { missingFields.append("Activity") }
                        }
                        
                        // 누락된 필드가 있으면 구체적으로 로그를 남기고 해당 행은 건너뜁니다.
                        if !missingFields.isEmpty {
                            self.debugLog("이벤트 변환 실패 - 누락된 필드: \(missingFields.joined(separator: ", ")) (행: \(try columns.text()))")
                            continue
                        }
                        
                        // 공항, 시간 등 문자열 파싱
                        func extractAirportAndTime(_ fullString: String) -> (String, String, String) {
                            let pattern = #"([A-Z]{3})\s+(\d{2}:\d{2})(\([-+]\d+\))?"#
                            let regex = try? NSRegularExpression(pattern: pattern)
                            if let regex = regex {
                                let range = NSRange(fullString.startIndex..., in: fullString)
                                if let match = regex.firstMatch(in: fullString, options: [], range: range) {
                                    let airport = match.range(at: 1).location != NSNotFound ?
                                        String(fullString[Range(match.range(at: 1), in: fullString)!]) : "N/A"
                                    let time = match.range(at: 2).location != NSNotFound ?
                                        String(fullString[Range(match.range(at: 2), in: fullString)!]) : "N/A"
                                    let option = match.range(at: 3).location != NSNotFound ?
                                        String(fullString[Range(match.range(at: 3), in: fullString)!]) : ""
                                    self.debugLog("extractAirportAndTime: \(fullString) -> \(airport), \(time), \(option)")
                                    return (airport, time, option)
                                }
                            }
                            return ("N/A", "N/A", "")
                        }
                        
                        let (depAp, depStnTime, depStnTimeOpt) = extractAirportAndTime(depStationTimeFull)
                        let (arrAp, arrStnTime, arrStnTimeOpt) = extractAirportAndTime(arrStationTimeFull)
                        
                        let depDate = calculateDate(baseDate: date, option: depStnTimeOpt)
                        let arrDate = calculateDate(baseDate: date, option: arrStnTimeOpt)
                        let dutyDebriefTimeExtracted = extractDutyDebriefTime(dutyDebrief)
                        let dutyDebriefOption = extractDutyDebriefOption(dutyDebrief)
                        let dutyDebriefDate = calculateDate(baseDate: date, option: dutyDebriefOption.isEmpty ? "" : "(\(dutyDebriefOption))")
                        
                        let seq = (sequenceCounter[date] ?? 0) + 1
                        sequenceCounter[date] = seq
                        
                        let depTimeUTC = (depStnTime != "") ? self.convertLocalTimeToUTCTime(dateString: depDate, timeString: depStnTime, airportCode: depAp, airports: airports) : "N/A"
                        let arrTimeUTC = (arrStnTime != "") ? self.convertLocalTimeToUTCTime(dateString: arrDate, timeString: arrStnTime, airportCode: arrAp, airports: airports) : "N/A"
                        
                        let scheduleEntry: [String: String] = [
                            "Seq": "\(seq)",
                            "Activity": activity,
                            "Item": item,
                            "WorkType": workType,
                            "DutyReport": dutyReport,
                            "DepAp": depAp,
                            "DepStnTime": depStnTime.isEmpty ? "N/A" : depStnTime,
                            "DepStnTimeOpt": depStnTimeOpt,
                            "DepDate": depDate,
                            "ArrAp": arrAp,
                            "ArrStnTime": arrStnTime.isEmpty ? "N/A" : arrStnTime,
                            "ArrStnTimeOpt": arrStnTimeOpt,
                            "ArrDate": arrDate,
                            "DutyDebrief": dutyDebrief,
                            "DutyDebriefTime": dutyDebriefTimeExtracted,
                            "DutyDebriefDate": dutyDebriefDate,
                            "FlyingHours": flyingHours,
                            "DutyHours": dutyHours,
                            "SDC": sdc,
                            "Hotel": hotel,
                            "DepStnTimeUTC": depTimeUTC,
                            "ArrStnTimeUTC": arrTimeUTC,
                            "Date": date
                        ]
                        
                        extractedSchedules[date, default: []].append(scheduleEntry)
                        self.debugLog("추출된 스케줄 추가: \(scheduleEntry)")
                        
                        if let depDateObj = dateFormatter.date(from: depDate) {
                            let monthKey = self.formattedMonth(for: depDateObj)
                            depMonthCount[monthKey, default: 0] += 1
                        }
                    }
                }
                
                if extractedSchedules.isEmpty {
                    DispatchQueue.main.async {
                        self.showAlert(title: "Import Fail", message: "NO SKD on Webview!\nPlease Go to ROSTER > ROSTER CALENDAR > ROSTER REPORT ...")
                    }
                    return
                }
                
                if let maxEntry = depMonthCount.max(by: { $0.value < $1.value }) {
                    let majorityMonthKey = maxEntry.key
                    self.debugLog("출발 스케줄이 가장 많은 달: \(majorityMonthKey)")
                    var monthlyHours = UserDefaults.standard.dictionary(forKey: self.totalHoursByMonthUserDefaultsKey) as? [String: String] ?? [:]
                    monthlyHours[majorityMonthKey] = self.totalHours
                    UserDefaults.standard.set(monthlyHours, forKey: self.totalHoursByMonthUserDefaultsKey)
                    self.totalHours = monthlyHours[majorityMonthKey] ?? ""
                }
                
                DispatchQueue.main.async {
                    self.schedules.merge(extractedSchedules) { (_, new) in new }
                    self.saveSchedules()
                    self.printSchedulesToConsole()
                    self.showAlert(title: "Import Complete", message: "The schedule was successfully imported.")
                }
                
            } catch {
                self.debugLog("HTML 파싱 오류: \(error)")
                DispatchQueue.main.async {
                    self.showAlert(title: "Import Fail", message: "Failed to Import schedule.(HTML parsing error)")
                }
            }
        }
    }
    
    // MARK: - 콘솔 출력, 알림, 스케줄 추가 등 기타 함수
    func printSchedulesToConsole() {
        self.debugLog("----- 저장된 스케줄 출력 -----")
        for (date, entries) in schedules {
            self.debugLog("날짜: \(date)")
            for entry in entries {
                self.debugLog("스케줄: \(entry)")
            }
        }
        self.debugLog("----- 출력 완료 -----")
    }
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func addScheduleToStackView(date: String, activity: String) {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let dateLabel = UILabel()
        dateLabel.text = date
        dateLabel.font = UIFont.boldSystemFont(ofSize: 16)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let activityLabel = UILabel()
        activityLabel.text = activity
        activityLabel.font = UIFont.systemFont(ofSize: 14)
        activityLabel.textColor = .gray
        activityLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(dateLabel)
        containerView.addSubview(activityLabel)
        
        NSLayoutConstraint.activate([
            dateLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            activityLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            activityLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 4),
            activityLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        scheduleStackView.addArrangedSubview(containerView)
    }
    
    // MARK: - 캘린더 이벤트 추가 함수
    func addEventToCalendar(for scheduleEntry: [String: String], airports: [[String: Any]]?) {
        let koreanTimeZone = TimeZone(identifier: "Asia/Seoul")!
        let workType = scheduleEntry["WorkType"] ?? ""
        
        var eventTitle: String = ""
        var startDate: Date?
        var endDate: Date?
        var eventTimeZone: TimeZone = koreanTimeZone
        
        if workType == "FLY" || workType == "TVL" {
            // 비행 듀티 이벤트 처리
            guard let item = scheduleEntry["Item"],
                  let depStnTime = scheduleEntry["DepStnTime"],
                  let depAp = scheduleEntry["DepAp"],
                  let arrAp = scheduleEntry["ArrAp"],
                  let arrStnTime = scheduleEntry["ArrStnTime"],
                  let depDateString = scheduleEntry["DepDate"],
                  let arrDateString = scheduleEntry["ArrDate"] else {
                self.debugLog("비행 듀티 이벤트 변환 실패 - 필요한 데이터 누락: \(scheduleEntry)")
                return
            }
            
            // TVL인 경우, 항목(item) 앞의 두 글자를 "DH"로 변경
            var modifiedItem = item
            if workType == "TVL" {
                if item.count >= 2 {
                    modifiedItem = "DH" + item.dropFirst(2)
                } else {
                    modifiedItem = "DH" + item
                }
            }
            
            // 기본 제목 생성
            let baseTitle = "\(modifiedItem) \(depStnTime) \(depAp) - \(arrAp) \(arrStnTime)"
            
            if let airports = airports,
               let depTimeZone = timeZoneForAirport(iata: depAp, airports: airports),
               let departureDate = dateFromLocal(dateString: depDateString, timeString: depStnTime, timeZone: depTimeZone),
               let arrTimeZone = timeZoneForAirport(iata: arrAp, airports: airports),
               let arrivalDate = dateFromLocal(dateString: arrDateString, timeString: arrStnTime, timeZone: arrTimeZone) {
                startDate = departureDate
                endDate = arrivalDate
                eventTimeZone = depTimeZone
                self.debugLog("비행 듀티 이벤트 변환 성공: \(baseTitle)")
            } else {
                self.debugLog("공항 타임존 변환 실패 for \(depAp) 또는 \(arrAp)")
                return
            }
            
            // 비행 듀티의 경우, 노트에 첫 줄에 baseTitle (즉, 제목과 동일한 항목)을 넣고,
            // TVL이면 첫 줄에 "Deadhead"를 먼저 추가한 후, 그 다음 줄부터 추가 정보를 붙입니다.
            var noteText = ""
            if workType == "TVL" {
                noteText += "Deadhead\n"
            }
            // 제목(기본 제목)도 포함
            noteText += baseTitle
            
            // 추가 정보가 있다면 줄바꿈 후 추가
            if let dutyReport = scheduleEntry["DutyReport"], !dutyReport.isEmpty {
                noteText += "\nShow Up: \(dutyReport)"
            }
            if let flyingHours = scheduleEntry["FlyingHours"], !flyingHours.isEmpty {
                noteText += "\nFlyingHours: \(flyingHours)"
            }
            if let dutyHours = scheduleEntry["DutyHours"], !dutyHours.isEmpty {
                noteText += "\nDutyHours: \(dutyHours)"
            }
            if let sdc = scheduleEntry["SDC"], !sdc.isEmpty {
                noteText += "\nSDC: \(sdc)"
            }
            if let hotel = scheduleEntry["Hotel"], !hotel.isEmpty {
                noteText += "\nHotel: \(hotel)"
            }
            
            // 최종적으로 eventTitle은 baseTitle (제목은 변하지 않음)
            eventTitle = baseTitle
            
            self.debugLog("최종 noteText (비행 듀티): \(noteText)")
            
        } else {
            // 그라운드 듀티 이벤트 처리:
            // 시작: DepAp 기준 – DepDate (로컬 시작 날짜)와 DutyReport (로컬 시작 시간)
            // 종료: ArrAp 기준 – DutyDebriefDate (로컬 종료 날짜)와 DutyDebriefTime (로컬 종료 시간)
            guard let dutyReport = scheduleEntry["DutyReport"],
                  let dutyDebriefTime = scheduleEntry["DutyDebriefTime"],
                  let dutyDebriefDate = scheduleEntry["DutyDebriefDate"],
                  let depAp = scheduleEntry["DepAp"],
                  let arrAp = scheduleEntry["ArrAp"],
                  let depDateString = scheduleEntry["DepDate"],
                  let activity = scheduleEntry["Activity"] else {
                self.debugLog("그라운드 듀티 이벤트 변환 실패 - 필요한 데이터 누락: \(scheduleEntry)")
                return
            }
            let baseTitle = "\(activity) \(dutyReport) - \(dutyDebriefTime)"
            eventTitle = baseTitle
            // 시작 이벤트 계산 (DepAp 기준)
            guard let startTimeZone = timeZoneForAirport(iata: depAp, airports: airports ?? []),
                  let start = dateFromLocal(dateString: depDateString, timeString: dutyReport, timeZone: startTimeZone) else {
                self.debugLog("그라운드 듀티 시작 시간 변환 실패 for DepAp: \(depAp), DepDate: \(depDateString), DutyReport: \(dutyReport)")
                return
            }
            // 종료 이벤트 계산 (ArrAp 기준)
            guard let endTimeZone = timeZoneForAirport(iata: arrAp, airports: airports ?? []),
                  let end = dateFromLocal(dateString: dutyDebriefDate, timeString: dutyDebriefTime, timeZone: endTimeZone) else {
                self.debugLog("그라운드 듀티 종료 시간 변환 실패 for ArrAp: \(arrAp), DutyDebriefDate: \(dutyDebriefDate), DutyDebriefTime: \(dutyDebriefTime)")
                return
            }
            startDate = start
            endDate = end
            // 이벤트 타임존은 시작 기준(DepAp)을 사용
            eventTimeZone = startTimeZone
            self.debugLog("그라운드 듀티 이벤트 변환 성공: \(baseTitle)")
            
            // 그라운드 듀티의 경우 노트의 첫 줄은 제목(baseTitle)과 동일하고, 그 다음 줄에 SDC 값(있는 경우) 추가
            var noteText = baseTitle
            if let sdc = scheduleEntry["SDC"], !sdc.isEmpty {
                noteText += "\nSDC: \(sdc)"
            }
            
            self.debugLog("최종 noteText (그라운드 듀티): \(noteText)")
        }
        
        guard let start = startDate, let end = endDate else { return }
        
        // EKEvent 객체 생성 후 할당
        let event = EKEvent(eventStore: self.eventStore)
        if workType == "FLY" || workType == "TVL" {
            event.title = eventTitle
            event.notes = eventTitle + "\n" + ((workType == "TVL") ? "Deadhead\n" : "") +
                ((scheduleEntry["DutyReport"] ?? "").isEmpty ? "" : "Show Up: \(scheduleEntry["DutyReport"]!)\n") +
                ((scheduleEntry["FlyingHours"] ?? "").isEmpty ? "" : "FlyingHours: \(scheduleEntry["FlyingHours"]!)\n") +
                ((scheduleEntry["DutyHours"] ?? "").isEmpty ? "" : "DutyHours: \(scheduleEntry["DutyHours"]!)\n") +
                ((scheduleEntry["SDC"] ?? "").isEmpty ? "" : "SDC: \(scheduleEntry["SDC"]!)\n") +
                ((scheduleEntry["Hotel"] ?? "").isEmpty ? "" : "Hotel: \(scheduleEntry["Hotel"]!)")
        } else {
            event.title = eventTitle
            var noteText = eventTitle
            if let sdc = scheduleEntry["SDC"], !sdc.isEmpty {
                noteText += "\nSDC: \(sdc)"
            }
            event.notes = noteText
        }
        
        event.startDate = start
        event.endDate = end
        event.timeZone = eventTimeZone
        
        // 반드시 새로 생성한 캘린더(selectedCalendar)를 사용
        if let calendar = self.calendarManager.selectedCalendar {
            event.calendar = calendar
        } else if let defaultCal = self.eventStore.defaultCalendarForNewEvents {
            event.calendar = defaultCal
            self.debugLog("캘린더 선택 정보가 없어 기본 캘린더 사용: \(defaultCal.title)")
        } else {
            self.debugLog("캘린더가 설정되어 있지 않습니다.")
            return
        }
        
        self.calendarManager.saveEvent(event: event) { success, error in
            if success {
                self.savedEventCount += 1
                self.debugLog("Calendar event saved successfully: \(event.title ?? "No Title")\nSaved Calendar: \(event.calendar?.title ?? "N/A")\nTOTAL EVENT NO: \(self.savedEventCount)")
            } else {
                self.debugLog("Failed to save event: \(error?.localizedDescription ?? "UNKNOWN")")
            }
        }
    }
    
    // MARK: - 헬퍼 함수: ApList.json 파싱
    func loadAirportList() -> [[String: Any]]? {
        guard let path = Bundle.main.path(forResource: "ApList", ofType: "json") else {
            debugLog("ApList.json 경로 찾기 실패")
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                debugLog("ApList.json 파싱 성공: \(jsonArray.count)개의 공항 정보")
                return jsonArray
            }
        } catch {
            debugLog("ApList.json 로드 실패: \(error)")
        }
        return nil
    }
    
    // MARK: - 헬퍼 함수: IATA 코드로 타임존 생성
    func timeZoneForAirport(iata: String, airports: [[String: Any]]) -> TimeZone? {
        guard let airport = airports.first(where: { ($0["IATA"] as? String) == iata }),
              let utcOffset = airport["utc_offset"] as? Double else {
            debugLog("타임존 생성 실패: IATA(\(iata))에 해당하는 정보 없음")
            return nil
        }
        let seconds = Int(utcOffset * 3600)
        debugLog("타임존 생성: IATA(\(iata)) -> offset \(utcOffset) (\(seconds)초)")
        return TimeZone(secondsFromGMT: seconds)
    }
    
    // MARK: - 헬퍼 함수: 날짜, 시간 문자열과 타임존을 사용해 Date 객체 변환
    func dateFromLocal(dateString: String, timeString: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        let combined = "\(dateString) \(timeString)"
        if let date = formatter.date(from: combined) {
            debugLog("날짜 변환 성공: \(combined) -> \(date)")
            return date
        } else {
            debugLog("날짜 변환 실패: \(combined) (타임존: \(timeZone))")
            return nil
        }
    }
    
    // MARK: - 헬퍼 함수: 로컬 시간 -> UTC 시간 변환
    func convertLocalTimeToUTCTime(dateString: String, timeString: String, airportCode: String, airports: [[String: Any]]) -> String {
        guard let timeZone = timeZoneForAirport(iata: airportCode, airports: airports),
              let localDate = dateFromLocal(dateString: dateString, timeString: timeString, timeZone: timeZone) else {
            debugLog("convertLocalTimeToUTCTime 실패: airportCode(\(airportCode)) - \(dateString) \(timeString)")
            return "N/A"
        }
        let utcFormatter = DateFormatter()
        utcFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let utcString = utcFormatter.string(from: localDate)
        debugLog("convertLocalTimeToUTCTime 성공: \(dateString) \(timeString) -> \(utcString) (airportCode: \(airportCode))")
        return utcString
    }
}
