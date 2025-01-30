//
//  ViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/22.
//

import UIKit
import WebKit
import SwiftSoup

// ✅ SwiftSoup Elements 확장 (배열 인덱스 초과 방지)
extension Elements {
    func getOrNil(_ index: Int) -> String {
        return (self.size() > index) ? (try? self.get(index).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "N/A" : "N/A"
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    @IBOutlet weak var webView: WKWebView!
    var schedules: [String: [String: String]] = [:]
    var toolbar: UIToolbar!
    @IBOutlet weak var scheduleStackView: UIStackView! // 스택 뷰 연결
    
    // 첫 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func iflightButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/")
    }
    // 두 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func CrewLinkButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://crewlink.koreanair.com/")
    }
    // 세 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func ImportButtonTapped(_ sender: UIBarButtonItem) {
        importSchedule()
        print(schedules)
    }
    // 네 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func ViewListButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let viewListVC = storyboard.instantiateViewController(withIdentifier: "ViewListViewController") as? ViewListViewController {
            viewListVC.schedules = schedules // 스케줄 데이터 전달
            navigationController?.pushViewController(viewListVC, animated: true)
        }
    }

    // 다섯 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func PrintButtonTapped(_ sender: UIBarButtonItem) {
        print("Print")
    }
    
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // WebView delegate 설정
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // 네비게이션 바 스타일 변경
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Ocean")// Ocean
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white] // 타이틀 색상
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        // ✅ 특정 뷰 컨트롤러에서 네비게이션 바 스타일 직접 적용
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = .white // 백버튼 & 아이콘 색상

        // ✅ 네비게이션 바가 투명해지는 것을 방지
        navigationController?.navigationBar.isTranslucent = false
    }


    
    
    // 링크 클릭 시 현재 WebView에서 열리도록 설정
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            // 새 창을 열려고 하면 현재 웹뷰에서 로드
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    // 새 창 열기 방지 및 현재 WebView에서 열도록 설정
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // URL을 WebView에 로드하는 함수
    func loadURL(_ urlString: String) {
        print("loadURL 호출됨: \(urlString)") // 디버깅용 로그
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            print("잘못된 URL 형식: \(urlString)")
        }
    }


    // 스케줄을 가져오는 함수 지정
    func importSchedule() {
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { (html: Any?, error: Error?) in
            guard let htmlString = html as? String else {
                print("HTML 가져오기 실패")
                return
            }

            do {
                // ✅ HTML 파싱
                let doc: Document = try SwiftSoup.parse(htmlString)
                let rows: Elements = try doc.select("tr") // 모든 tr 행 선택

                var extractedSchedules: [String: [String: String]] = [:]
                var schedulerOwner: String = "Unknown"
                var scheduleTotalTime: String = "Unknown"
                var lastDate: String = "Unknown"
                var lastActivity: String = ""
                var lastDutyReport: String = ""
                var lastWorkType: String = ""

                // ✅ 시간 및 옵션 값을 분리하는 함수 (예: "01:28(+1)" -> "01:28" / "(+1)")
                func extractTimeAndOption(_ fullString: String) -> (String, String) {
                    let pattern = #"(\d{2}:\d{2})(\(\+\d+\))?"#
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let range = NSRange(fullString.startIndex..., in: fullString)
                        if let match = regex.firstMatch(in: fullString, options: [], range: range) {
                            let time = match.range(at: 1).location != NSNotFound ?
                                String(fullString[Range(match.range(at: 1), in: fullString)!]) : "N/A"
                            let option = match.range(at: 2).location != NSNotFound ?
                                String(fullString[Range(match.range(at: 2), in: fullString)!]) : ""
                            return (time, option)
                        }
                    }
                    return ("N/A", "")
                }

                // ✅ 공항 코드와 시간을 정확히 분리하는 함수
                func extractAirportAndTime(_ fullString: String) -> (String, String, String) {
                    let parts = fullString.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    let airport = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "N/A"
                    let fullTimeString = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    let (time, option) = extractTimeAndOption(fullTimeString)

                    if airport.count != 3 || !airport.allSatisfy({ $0.isLetter }) {
                        return ("N/A", time, option)
                    }
                    return (airport, time, option)
                }

                // ✅ 스케줄 데이터 추출
                for (_, row) in rows.enumerated() {
                    let columns: Elements = try row.select("td")

                    if columns.size() > 10, !(try columns[1].text().contains("Date")) {
                        var date = columns.getOrNil(1)
                        var activity = columns.getOrNil(2)
                        var item = columns.getOrNil(4)
                        var workType = columns.getOrNil(6)
                        var dutyReport = columns.getOrNil(3)
                        let depStationTimeFull = columns.getOrNil(8)
                        let arrStationTimeFull = columns.getOrNil(9)
                        let dutyDebrief = columns.getOrNil(11)
                        let flyingHours = columns.getOrNil(12)
                        let dutyHours = columns.getOrNil(13)

                        // ✅ 날짜가 비어있으면 바로 위 행의 날짜 사용
                        if date.isEmpty || date == "N/A" {
                            if lastDate == "Unknown" { continue }
                            date = lastDate
                        } else {
                            lastDate = date
                            lastActivity = ""
                            lastDutyReport = ""
                            lastWorkType = ""
                        }

                        // ✅ Activity가 비어있으면 마지막 Activity 사용
                        if activity.isEmpty || activity == "N/A" {
                            activity = lastActivity
                        } else {
                            lastActivity = activity
                        }

                        // ✅ DutyReport가 비어있으면 마지막 DutyReport 사용
                        if dutyReport.isEmpty || dutyReport == "N/A" {
                            dutyReport = lastDutyReport
                        } else {
                            lastDutyReport = dutyReport
                        }

                        // ✅ WorkType이 비어있으면 마지막 WorkType 사용
                        if workType.isEmpty || workType == "N/A" {
                            workType = lastWorkType
                        } else {
                            lastWorkType = workType
                        }

                        // ✅ 출발/도착 공항 코드 및 시간 + 옵션 분리
                        let (depAp, depStnTime, depStnTimeOpt) = extractAirportAndTime(depStationTimeFull)
                        let (arrAp, arrStnTime, arrStnTimeOpt) = extractAirportAndTime(arrStationTimeFull)

                        // ✅ DutyReport가 있어도 Item을 유지하도록 변경
                        if item.isEmpty || item == "N/A" {
                            item = ""
                        }

                        // ✅ 모든 값이 비어있는 경우 → 저장하지 않음
                        let values = [activity, item, workType, dutyReport, depStnTime, arrStnTime, dutyDebrief, flyingHours, dutyHours]
                        if values.allSatisfy({ $0.isEmpty || $0 == "N/A" }) {
                            continue
                        }

                        // ✅ 기존 값과 병합하여 저장 (같은 날짜가 있으면 덮어쓰지 않고 추가)
                        var scheduleEntry = extractedSchedules[date] ?? [:]
                        scheduleEntry["Activity"] = activity
                        scheduleEntry["Item"] = item
                        scheduleEntry["WorkType"] = workType
                        scheduleEntry["DutyReport"] = dutyReport
                        scheduleEntry["DepAp"] = depAp
                        scheduleEntry["DepStnTime"] = depStnTime.isEmpty ? "N/A" : depStnTime
                        scheduleEntry["DepStnTimeOpt"] = depStnTimeOpt
                        scheduleEntry["ArrAp"] = arrAp
                        scheduleEntry["ArrStnTime"] = arrStnTime.isEmpty ? "N/A" : arrStnTime
                        scheduleEntry["ArrStnTimeOpt"] = arrStnTimeOpt
                        scheduleEntry["DutyDebrief"] = dutyDebrief
                        scheduleEntry["FlyingHours"] = flyingHours
                        scheduleEntry["DutyHours"] = dutyHours

                        extractedSchedules[date] = scheduleEntry
                        
                        // ✅ "FH :"과 "DH :"이 포함된 정확한 <td> 요소를 찾기
                        for row in rows {
                            let columns = try row.select("td")

                            for column in columns {
                                let text = try column.text().trimmingCharacters(in: .whitespacesAndNewlines)

                                // ✅ 스케줄 소유자 찾기 (이름 + 직원번호 + 직급 정보 포함)
                                if text.contains("|") && text.contains("ICN") {  // "ICN"과 "|" 포함한 항목이 소유자 정보일 가능성 높음
                                    schedulerOwner = text
                                }

                                // ✅ 비행 시간 및 근무 시간 추출 (정규식 사용)
                                if text.contains("FH :") || text.contains("DH :") {
                                    // ✅ 정규식 패턴 수정 (FH : XX:XX | DH : XX:XX 형식)
                                    let regexPattern = #"FH\s*:\s*(\d{1,2}:\d{2})\s*\|\s*DH\s*:\s*(\d{1,2}:\d{2})"#

                                    do {
                                        let regex = try NSRegularExpression(pattern: regexPattern, options: [])
                                        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

                                        if let match = matches.first {
                                            // ✅ 정규식 그룹에서 정확한 FH 및 DH 값을 추출
                                            if let fhRange = Range(match.range(at: 1), in: text),
                                               let dhRange = Range(match.range(at: 2), in: text) {
                                                let flightHours = String(text[fhRange])
                                                let dutyHours = String(text[dhRange])
                                                scheduleTotalTime = "FH : \(flightHours) | DH : \(dutyHours)"  // ✅ 최종 값 설정
                                                break  // ✅ 값을 찾으면 반복 종료
                                            }
                                        }
                                    } catch {
                                        print("❌ 정규식 오류: \(error)")
                                    }
                                }
                            }
                        }



                        
                        // ✅ 디버깅용 로그 추가
                        print("📌 저장됨 - Date: \(date), Activity: \(activity), Item: \(item), WorkType: \(workType), DutyReport: \(dutyReport), DepAp: \(depAp), DepStnTime: \(depStnTime), DepStnTimeOpt: \(depStnTimeOpt),ArrAp: \(arrAp), ArrStnTime: \(arrStnTime), ArrStnTimeOpt: \(arrStnTimeOpt), DutyDebrief: \(dutyDebrief), FlyingHours: \(flyingHours), DutyHours: \(dutyHours)")
                    }
                }

                // ✅ 메인 스레드에서 UI 업데이트
                DispatchQueue.main.async {
                    self.schedules = extractedSchedules
                    let schedulerOwnerVariable = schedulerOwner
                    let scheduleTotalTimeVariable = scheduleTotalTime
                    print("📌 스케줄 소유자: \(schedulerOwnerVariable)")
                    print("📌 총 비행 시간 및 근무 시간: \(scheduleTotalTimeVariable)")
                }

            } catch {
                print("HTML 파싱 오류: \(error)")
            }
        }
    }













    // 스케줄 추가 메서드
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
