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

// SwiftSoup의 Elements 배열에 안전하게 접근할 수 있도록 확장 (인덱스 초과 방지)
extension Elements {
    func getOrNil(_ index: Int) -> String {
        return (self.size() > index) ? (try? self.get(index).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "N/A" : "N/A"
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    
    // 스토리보드에서 연결된 WebView
    @IBOutlet weak var webView: WKWebView!
    
    // 날짜별로 여러 스케줄을 저장하는 딕셔너리 (UserDefaults에 영구 저장)
    var schedules: [String: [[String: String]]] = [:]
    
    // 스토리보드에서 연결된 스케줄을 보여주는 스택뷰
    @IBOutlet weak var scheduleStackView: UIStackView!
    
    // UserDefaults에 저장할 때 사용할 key들
    let schedulesUserDefaultsKey = "schedules"
    let ownerUserDefaultsKey = "ownerInfo"
    let totalHoursUserDefaultsKey = "totalHours"
    
    // 사용자 정보와 총 시간을 저장할 프로퍼티 선언
    var ownerInfo: String = ""
    var totalHours: String = ""
    
    // MARK: - UIBarButtonItem 액션들
   
    // 0. Input 버튼: 스케줄 입력 달력 화면으로 이동 (날짜 선택 후 입력 팝업을 띄움)
    @IBAction func InputButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        // ScheduleInputCalendarViewController : 달력에서 날짜 선택 후 스케줄 입력 팝업 호출
        if let inputCalendarVC = storyboard.instantiateViewController(withIdentifier: "ScheduleInputCalendarViewController") as? ScheduleInputCalendarViewController {
            navigationController?.pushViewController(inputCalendarVC, animated: true)
        }
    }
    
    // 1. iFlight 버튼: iFlight URL을 로드
    @IBAction func iflightButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/")
    }
    
    /*
    // CrewLink 버튼: 필요시 사용 (CrewLink URL 로드)
    @IBAction func CrewLinkButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://crewlink.koreanair.com/")
    }
    */
    
    // 3. Import 버튼: 스케줄 파싱 및 가져오기
    @IBAction func ImportButtonTapped(_ sender: UIBarButtonItem) {
        importSchedule()
    }
    
    // 4. View List 버튼: 스케줄 목록 화면으로 이동
    @IBAction func ViewListButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let viewListVC = storyboard.instantiateViewController(withIdentifier: "ViewListViewController") as? ViewListViewController {
            viewListVC.schedules = schedules // 스케줄 데이터 전달
            navigationController?.pushViewController(viewListVC, animated: true)
        }
    }
    
    // 5. Calendar 버튼: 달력 보기 화면으로 이동
    @IBAction func CalendarButtonTapped(_ sender: UIBarButtonItem) {
        print("CalendarButtonTapped")
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let calendarVC = storyboard.instantiateViewController(withIdentifier: "MonthlyCalendarViewController") as? MonthlyCalendarViewController {
            calendarVC.schedules = schedules
            // 소유자 정보와 총 시간 정보를 전달 (또는 MonthlyCalendarViewController에서 UserDefaults에서 불러올 수 있음)
            calendarVC.ownerInfo = self.ownerInfo
            calendarVC.totalHours = self.totalHours
            navigationController?.pushViewController(calendarVC, animated: true)
        }
    }
    
    // MARK: - View LifeCycle
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 웹뷰 델리게이트 설정
        webView.navigationDelegate = self
        webView.uiDelegate = self
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSchedules() // 저장된 스케줄 불러오기
        
        // 네비게이션 바 스타일 설정 (배경색, 글자색 등)
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
        
        // 기존 저장된 스케줄을 콘솔에 출력
        printSchedulesToConsole()
    }
    
    // MARK: - WebView Delegate Methods
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 새 창이 열리려는 경우 현재 웹뷰에서 로드
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 새 창 요청 시 URL을 로드
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    
    func loadURL(_ urlString: String) {
        print("loadURL 호출됨: \(urlString)")
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            print("잘못된 URL 형식: \(urlString)")
        }
    }
    
    // MARK: - 영구 저장 기능 (UserDefaults)
    
    func saveSchedules() {
        do {
            let data = try JSONEncoder().encode(schedules)
            UserDefaults.standard.set(data, forKey: schedulesUserDefaultsKey)
            print("스케줄 저장 성공")
        } catch {
            print("스케줄 저장 실패: \(error)")
        }
    }
    
    func loadSchedules() {
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
                print("스케줄 불러오기 성공")
            } catch {
                print("스케줄 불러오기 실패: \(error)")
            }
        } else {
            print("저장된 스케줄이 없습니다.")
        }
    }
    
    // MARK: - 스케줄 가져오기 (Import) 기능
    
    func importSchedule() {
        // ApList.json에서 공항 정보 로드 (정밀한 DST 처리를 위해 필요)
        guard let airports = loadAirportList() else {
            print("ApList.json 로딩 실패")
            DispatchQueue.main.async {
                self.showAlert(title: "Import Fail", message: "공항 정보 로딩에 실패했습니다.")
            }
            return
        }
        
        // 웹뷰의 HTML 전체를 가져와 SwiftSoup으로 파싱
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { (html: Any?, error: Error?) in
            guard let htmlString = html as? String else {
                print("❌ HTML 가져오기 실패")
                DispatchQueue.main.async {
                    self.showAlert(title: "가져오기 실패", message: "스케줄을 가져오지 못했습니다.")
                }
                return
            }
            
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
                
                // 날짜 계산: 기본 날짜에 옵션(예: +1, -1)을 적용
                func calculateDate(baseDate: String, option: String) -> String {
                    guard let baseDateObj = dateFormatter.date(from: baseDate) else { return baseDate }
                    let pattern = #"([-+]\d+)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: option, range: NSRange(option.startIndex..., in: option)) {
                        let matchRange = Range(match.range, in: option)!
                        let offsetString = String(option[matchRange]).replacingOccurrences(of: "+", with: "")
                        if let offset = Int(offsetString),
                           let newDate = calendar.date(byAdding: .day, value: offset, to: baseDateObj) {
                            return dateFormatter.string(from: newDate)
                        }
                    }
                    return baseDate
                }
                
                func extractDutyDebriefOption(_ dutyDebrief: String) -> String {
                    let pattern = #"\s*\(([-+]\d+)\)\s*$"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: dutyDebrief, range: NSRange(dutyDebrief.startIndex..., in: dutyDebrief)),
                       let range = Range(match.range(at: 1), in: dutyDebrief) {
                        return String(dutyDebrief[range])
                    }
                    return ""
                }
                
                func extractDutyDebriefTime(_ dutyDebrief: String) -> String {
                    let possibleOpeningParens: [Character] = ["(", "（"]
                    if let index = dutyDebrief.firstIndex(where: { possibleOpeningParens.contains($0) }) {
                        let timePart = dutyDebrief[..<index].trimmingCharacters(in: .whitespaces)
                        return String(timePart.prefix(5))
                    }
                    return String(dutyDebrief.trimmingCharacters(in: .whitespaces).prefix(5))
                }
                
                // 소유자 정보 추출 (첫 번째 "|" 이전의 텍스트만 사용)
                do {
                    if let ownerElement = try doc.select("body > table > tbody > tr > td:nth-child(2) > table:nth-child(2) > tbody > tr:nth-child(3) > td:nth-child(4) > p > span").first() {
                        let fullOwnerText = try ownerElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if let pipeRange = fullOwnerText.range(of: "|") {
                            self.ownerInfo = String(fullOwnerText[..<pipeRange.lowerBound])
                        } else {
                            self.ownerInfo = fullOwnerText
                        }
                        print("사용자 정보: \(self.ownerInfo)")
                    } else {
                        print("소유자 정보를 찾을 수 없습니다.")
                    }
                } catch {
                    print("소유자 정보 추출 중 오류 발생: \(error)")
                }
                
                // 총 시간 정보 추출
                do {
                    if let hoursElement = try doc.select("body > table > tbody > tr > td:nth-child(2) > table:nth-child(2) > tbody > tr:nth-child(3) > td:nth-child(5) > p > span").first() {
                        self.totalHours = try hoursElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        print("총 시간: \(self.totalHours)")
                    } else {
                        print("총 시간 정보를 찾을 수 없습니다.")
                    }
                } catch {
                    print("총 시간 정보 추출 중 오류 발생: \(error)")
                }
                
                // UserDefaults에 소유자 및 총 시간 저장
                UserDefaults.standard.set(self.ownerInfo, forKey: self.ownerUserDefaultsKey)
                UserDefaults.standard.set(self.totalHours, forKey: self.totalHoursUserDefaultsKey)
                
                // 각 tr 행을 순회하며 스케줄 데이터 추출
                for (_, row) in rows.enumerated() {
                    let columns: Elements = try row.select("td")
                    
                    if columns.size() > 10, !(try columns[1].text().contains("Date")) {
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
                        let hotel = columns.getOrNil(16)
                        
                        if date.isEmpty || date == "N/A" {
                            if lastDate == "Unknown" { continue }
                            date = lastDate
                        } else {
                            lastDate = date
                        }
                        
                        if activity.isEmpty && workType.isEmpty {
                            continue
                        }
                        
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
                                    return (airport, time, option)
                                }
                            }
                            return ("N/A", "N/A", "")
                        }
                        
                        let (depAp, depStnTime, depStnTimeOpt) = extractAirportAndTime(depStationTimeFull)
                        let (arrAp, arrStnTime, arrStnTimeOpt) = extractAirportAndTime(arrStationTimeFull)
                        
                        let depDate = calculateDate(baseDate: date, option: depStnTimeOpt)
                        let arrDate = calculateDate(baseDate: date, option: arrStnTimeOpt)
                        let dutyDebriefTime = extractDutyDebriefTime(dutyDebrief)
                        let dutyDebriefOption = extractDutyDebriefOption(dutyDebrief)
                        let dutyDebriefDate = calculateDate(baseDate: date, option: dutyDebriefOption.isEmpty ? "" : "(\(dutyDebriefOption))")
                        
                        let seq = (sequenceCounter[date] ?? 0) + 1
                        sequenceCounter[date] = seq
                        
                        // ApList.json을 기반으로 로컬 시간 -> UTC 변환 수행 (정밀한 DST 처리)
                        let depTimeUTC = (depStnTime != "N/A") ? convertLocalTimeToUTCTime(dateString: depDate, timeString: depStnTime, airportCode: depAp, airports: airports) : "N/A"
                        let arrTimeUTC = (arrStnTime != "N/A") ? convertLocalTimeToUTCTime(dateString: arrDate, timeString: arrStnTime, airportCode: arrAp, airports: airports) : "N/A"
                        
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
                            "DutyDebriefTime": dutyDebriefTime,
                            "DutyDebriefDate": dutyDebriefDate,
                            "FlyingHours": flyingHours,
                            "DutyHours": dutyHours,
                            "Hotel": hotel,
                            "DepStnTimeUTC": depTimeUTC,
                            "ArrStnTimeUTC": arrTimeUTC
                        ]
                        
                        extractedSchedules[date, default: []].append(scheduleEntry)
                    }
                }
                
                if extractedSchedules.isEmpty {
                    DispatchQueue.main.async {
                        self.showAlert(
                            title: "Import Fail",
                            message: "NO SKD on Webview!\nPlease Go to ROSTER > ROSTER CALENDAR > ROSTER REPORT (Roster Report BUTTON @ Right Bottom).\nSelect Format to HTML then Run.\nWhen the screen changes to HTML format, CLICK the IMPORT BUTTON."
                        )
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.schedules.merge(extractedSchedules) { (_, new) in new }
                    self.saveSchedules()
                    // 콘솔에 스케줄 출력
                    self.printSchedulesToConsole()
                    self.showAlert(title: "Import Complete", message: "The schedule was successfully imported.")
                }
                
            } catch {
                print("HTML 파싱 오류: \(error)")
                DispatchQueue.main.async {
                    self.showAlert(title: "Import Fail", message: "Failed to Import schedule.(HTML parsing error)")
                }
            }
        }
    }
    
    // MARK: - 콘솔에 스케줄을 출력하는 함수
    func printSchedulesToConsole() {
        print("----- 저장된 스케줄 출력 -----")
        for (date, entries) in schedules {
            print("날짜: \(date)")
            for entry in entries {
                print("스케줄: \(entry)")
            }
        }
        print("----- 출력 완료 -----")
    }
    
    // MARK: - 알림창 표시 함수
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - 스케줄 추가 (예시)
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
}
