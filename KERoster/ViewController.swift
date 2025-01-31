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

// ✅ SwiftSoup Elements 확장 (배열 인덱스 초과 방지)
extension Elements {
    func getOrNil(_ index: Int) -> String {
        return (self.size() > index) ? (try? self.get(index).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "N/A" : "N/A"
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    @IBOutlet weak var webView: WKWebView!
    var schedules: [String: [[String: String]]] = [:] // ✅ 변경된 스케줄 타입 (배열 포함)
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

  /*
    // ✅ HTML에서 스케줄 소유자 및 총 비행 시간(FH/DH)을 추출하는 함수 (위치 기반)
    func findCrewTime(htmlString: String) -> (String, String) {
        do {
            let document = try SwiftSoup.parse(htmlString)
            let allTdElements = try document.select("td") // 모든 <td> 요소 선택

            // ✅ 위치 기반 인덱스 설정 (HTML 구조에 따라 조정 가능)
            let schedulerOwnerIndex = 17 // (스케줄 소유자 위치)
            let scheduleTotalTimeIndex = 20 // (총 비행 시간 및 근무 시간 위치)

            let schedulerOwner = schedulerOwnerIndex < allTdElements.count ?
                try allTdElements[schedulerOwnerIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : "N/A"

            let scheduleTotalTime = scheduleTotalTimeIndex < allTdElements.count ?
                try allTdElements[scheduleTotalTimeIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : "N/A"

            print (schedulerOwner, scheduleTotalTime)
            return (schedulerOwner, scheduleTotalTime)

        } catch {
            print("HTML 파싱 오류: \(error)")
            return ("N/A", "N/A")
        }
    }
*/
    // ✅ importSchedule 수정 (기존 기능 유지 + DepDate/ArrDate 업데이트)
    func importSchedule() {
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { (html: Any?, error: Error?) in
            guard let htmlString = html as? String else {
                print("❌ HTML 가져오기 실패")
                DispatchQueue.main.async {
                    self.showAlert(title: "가져오기 실패", message: "스케줄을 가져오지 못했습니다.")
                }
                return
            }

            do {
                // ✅ HTML 파싱
                let doc: Document = try SwiftSoup.parse(htmlString)
                let rows: Elements = try doc.select("tr") // 모든 tr 행 선택

                var extractedSchedules: [String: [[String: String]]] = [:] // ✅ 날짜별 여러 개의 스케줄 저장

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd-MMM-yyyy"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                var lastDate: String = "Unknown"
                var sequenceCounter: [String: Int] = [:] // ✅ 날짜별 순번 저장

                let calendar = Calendar.current // ✅ 날짜 연산을 위한 Calendar 객체

                // ✅ 날짜 계산 함수 (DepDate, ArrDate 계산)
                func calculateDate(baseDate: String, option: String) -> String {
                    guard let baseDateObj = dateFormatter.date(from: baseDate) else { return baseDate }

                    // ✅ 정규식으로 `(+1)`, `(+2)` 형태의 값을 추출
                    let pattern = #"(\+\d+)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: option, range: NSRange(option.startIndex..., in: option)) {
                        let matchRange = Range(match.range, in: option)!
                        let offsetString = String(option[matchRange]).replacingOccurrences(of: "+", with: "")
                        
                        if let offset = Int(offsetString) {
                            if let newDate = calendar.date(byAdding: .day, value: offset, to: baseDateObj) {
                                return dateFormatter.string(from: newDate)
                            }
                        }
                    }

                    return baseDate
                }

                // ✅ 스케줄 데이터 추출
                for (_, row) in rows.enumerated() {
                    let columns: Elements = try row.select("td")

                    if columns.size() > 10, !(try columns[1].text().contains("Date")) {
                        var date = columns.getOrNil(1)
                        let activity = columns.getOrNil(2)
                        let item = columns.getOrNil(4)
                        let workType = columns.getOrNil(6)
                        let dutyReport = columns.getOrNil(3)
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
                        }

                        // ✅ 공항 코드와 시간을 정확히 분리하는 함수
                        func extractAirportAndTime(_ fullString: String) -> (String, String, String) {
                            let pattern = #"([A-Z]{3})\s+(\d{2}:\d{2})(\(\+\d+\))?"#
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

                        // ✅ 출발/도착 공항 코드 및 시간 + 옵션 분리
                        let (depAp, depStnTime, depStnTimeOpt) = extractAirportAndTime(depStationTimeFull)
                        let (arrAp, arrStnTime, arrStnTimeOpt) = extractAirportAndTime(arrStationTimeFull)

                        // ✅ DepDate, ArrDate 업데이트
                        let depDate = calculateDate(baseDate: date, option: depStnTimeOpt)
                        let arrDate = calculateDate(baseDate: date, option: arrStnTimeOpt)

                        // ✅ 날짜별로 순번 증가
                        let seq = (sequenceCounter[date] ?? 0) + 1
                        sequenceCounter[date] = seq

                        // ✅ 스케줄 객체 생성 (순번 포함)
                        let scheduleEntry: [String: String] = [
                            "Seq": "\(seq)",  // ✅ 순번 추가
                            "Activity": activity,
                            "Item": item,
                            "WorkType": workType,
                            "DutyReport": dutyReport,
                            "DepAp": depAp,
                            "DepStnTime": depStnTime.isEmpty ? "N/A" : depStnTime,
                            "DepStnTimeOpt": depStnTimeOpt,
                            "DepDate": depDate,  // ✅ DepDate 추가
                            "ArrAp": arrAp,
                            "ArrStnTime": arrStnTime.isEmpty ? "N/A" : arrStnTime,
                            "ArrStnTimeOpt": arrStnTimeOpt,
                            "ArrDate": arrDate,  // ✅ ArrDate 추가
                            "DutyDebrief": dutyDebrief,
                            "FlyingHours": flyingHours,
                            "DutyHours": dutyHours
                        ]

                        // ✅ 같은 날짜에 여러 개 추가 가능하도록 배열로 저장
                        extractedSchedules[date, default: []].append(scheduleEntry)
                    }
                }

                // ✅ UI 업데이트
                DispatchQueue.main.async {
                    self.schedules = extractedSchedules
                    self.showAlert(title: "가져오기 완료", message: "스케줄을 성공적으로 가져왔습니다.")
                }

            } catch {
                print("HTML 파싱 오류: \(error)")
                DispatchQueue.main.async {
                    self.showAlert(title: "가져오기 실패", message: "스케줄을 가져오지 못했습니다.")
                }
            }
        }
    }





    // ✅ 알림창을 띄우는 함수
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
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
