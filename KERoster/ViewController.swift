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
        // 배열의 크기가 index보다 크면 해당 요소의 텍스트를 반환하고, 그렇지 않으면 "N/A" 반환
        return (self.size() > index) ? (try? self.get(index).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "N/A" : "N/A"
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    
    // 스토리보드에서 연결된 WebView
    @IBOutlet weak var webView: WKWebView!
    
    // 날짜별로 여러 스케줄을 저장하는 딕셔너리
    var schedules: [String: [[String: String]]] = [:]
    
    // 툴바 (필요 시 사용)
    var toolbar: UIToolbar!
    
    // 스토리보드에서 연결된 스케줄을 보여주는 스택뷰
    @IBOutlet weak var scheduleStackView: UIStackView!
    
    // MARK: - UIBarButtonItem 액션들
    
    // 1. iFlight 버튼: iFlight URL을 로드
    @IBAction func iflightButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/")
    }
    
    // 2. CrewLink 버튼: CrewLink URL을 로드
    @IBAction func CrewLinkButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://crewlink.koreanair.com/")
    }
    
    // 3. Import 버튼: 스케줄 파싱 및 가져오기
    @IBAction func ImportButtonTapped(_ sender: UIBarButtonItem) {
        importSchedule()
        print(schedules) // 디버깅용: 가져온 스케줄 출력
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
        
        // 스토리보드에서 MonthlyCalendarViewController 인스턴스 생성 및 스케줄 데이터 전달
        if let calendarVC = storyboard.instantiateViewController(withIdentifier: "MonthlyCalendarViewController") as? MonthlyCalendarViewController {
            calendarVC.schedules = schedules
            navigationController?.pushViewController(calendarVC, animated: true)
        }
    }
    
    // MARK: - View LifeCycle
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // WebView의 delegate 설정
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // 초기 URL 로드 (로그인 페이지)
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // 네비게이션 바 스타일 설정 (배경색, 타이틀 색상 등)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Ocean") // 사용자 정의 색상
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        // 네비게이션 바에 적용 (표준, 스크롤 시, 압축 모드 모두)
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = .white // 백 버튼 및 아이콘 색상
        
        // 네비게이션 바의 투명도 비활성화
        navigationController?.navigationBar.isTranslucent = false
    }
    
    // MARK: - WebView Delegate Methods
    
    // 링크 클릭 시 새 창 대신 현재 WebView에서 열도록 설정
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    
    // 새 창 열기 방지: 새 창 대신 현재 웹뷰에서 열기
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    
    // URL 문자열을 받아 WebView에서 로드하는 함수
    func loadURL(_ urlString: String) {
        print("loadURL 호출됨: \(urlString)") // 디버깅용 로그
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            print("잘못된 URL 형식: \(urlString)")
        }
    }
    
    // MARK: - 스케줄 가져오기 (Import) 기능
    
    /// 웹뷰의 HTML 소스를 파싱하여 스케줄 데이터를 추출하는 함수
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
                // HTML 파싱
                let doc: Document = try SwiftSoup.parse(htmlString)
                let rows: Elements = try doc.select("tr") // 모든 tr 행 선택

                var extractedSchedules: [String: [[String: String]]] = [:] // 날짜별 스케줄 저장

                // 날짜 포맷터 설정 ("dd-MMM-yyyy" 형식, 영어 로케일)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd-MMM-yyyy"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                var lastDate: String = "Unknown"
                var sequenceCounter: [String: Int] = [:] // 동일 날짜의 순번 저장

                let calendar = Calendar.current // 날짜 연산을 위한 Calendar 객체

                // DepDate와 ArrDate 계산을 위한 함수
                // baseDate: HTML에서 추출한 기본 날짜
                // option: 옵션 문자열 (예: "(+1)" 또는 "(-1)")가 포함될 수 있음
                func calculateDate(baseDate: String, option: String) -> String {
                    // baseDate를 Date 객체로 변환
                    guard let baseDateObj = dateFormatter.date(from: baseDate) else { return baseDate }
                    
                    // 정규식 패턴: 양수, 음수 모두 지원 (예: "+1", "-1")
                    let pattern = #"([-+]\d+)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: option, range: NSRange(option.startIndex..., in: option)) {
                        let matchRange = Range(match.range, in: option)!
                        // "+" 기호는 제거하고 "-"는 그대로 유지 (예: "+1" -> "1", "-1" -> "-1")
                        let offsetString = String(option[matchRange]).replacingOccurrences(of: "+", with: "")
                        if let offset = Int(offsetString) {
                            if let newDate = calendar.date(byAdding: .day, value: offset, to: baseDateObj) {
                                return dateFormatter.string(from: newDate)
                            }
                        }
                    }
                    // 옵션에서 오프셋을 찾지 못하면 기본 날짜를 그대로 반환
                    return baseDate
                }

                // 각 tr 행을 순회하며 스케줄 데이터 추출
                for (_, row) in rows.enumerated() {
                    let columns: Elements = try row.select("td")
                    
                    // 최소 11개 이상의 열이 있고, 제목 행("Date" 포함)이 아닌 경우에만 처리
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
                        
                        // 날짜가 비어있으면 바로 위 행의 날짜 사용
                        if date.isEmpty || date == "N/A" {
                            if lastDate == "Unknown" { continue }
                            date = lastDate
                        } else {
                            lastDate = date
                        }
                        
                        // 만약 Activity와 WorkType가 모두 비어 있으면 해당 스케줄은 저장하지 않고 건너뜁니다.
                        if activity.isEmpty && workType.isEmpty {
                            continue
                        }
                        
                        // 공항 코드와 시간을 정확히 분리하는 함수
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
                        
                        // 출발/도착 공항 및 시간, 옵션 분리
                        let (depAp, depStnTime, depStnTimeOpt) = extractAirportAndTime(depStationTimeFull)
                        let (arrAp, arrStnTime, arrStnTimeOpt) = extractAirportAndTime(arrStationTimeFull)
                        
                        // DepDate와 ArrDate 계산 (옵션에 따라 날짜 오프셋 적용)
                        let depDate = calculateDate(baseDate: date, option: depStnTimeOpt)
                        let arrDate = calculateDate(baseDate: date, option: arrStnTimeOpt)
                        
                        // 동일 날짜에 대해 순번 증가
                        let seq = (sequenceCounter[date] ?? 0) + 1
                        sequenceCounter[date] = seq
                        
                        // 스케줄 항목 객체 생성 (각 항목은 딕셔너리로 저장)
                        let scheduleEntry: [String: String] = [
                            "Seq": "\(seq)",  // 순번 추가
                            "Activity": activity,
                            "Item": item,
                            "WorkType": workType,
                            "DutyReport": dutyReport,
                            "DepAp": depAp,
                            "DepStnTime": depStnTime.isEmpty ? "N/A" : depStnTime,
                            "DepStnTimeOpt": depStnTimeOpt,
                            "DepDate": depDate,  // DepDate 저장
                            "ArrAp": arrAp,
                            "ArrStnTime": arrStnTime.isEmpty ? "N/A" : arrStnTime,
                            "ArrStnTimeOpt": arrStnTimeOpt,
                            "ArrDate": arrDate,  // ArrDate 저장
                            "DutyDebrief": dutyDebrief,
                            "FlyingHours": flyingHours,
                            "DutyHours": dutyHours
                        ]
                        
                        // 같은 날짜의 스케줄은 배열에 추가
                        extractedSchedules[date, default: []].append(scheduleEntry)
                    }
                }
                
                // 스케줄 데이터가 전혀 없는 경우 알림창 표시
                if extractedSchedules.isEmpty {
                    DispatchQueue.main.async {
                        self.showAlert(title: "가져오기 실패", message: "해당 웹뷰에 스케줄이 없습니다.")
                    }
                    return
                }
                
                // 기존 스케줄과 병합 (동일 날짜의 스케줄은 새로 가져온 데이터로 덮어쓰기)
                DispatchQueue.main.async {
                    self.schedules.merge(extractedSchedules) { (_, new) in new }
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
    
    // MARK: - 알림창 표시 함수
    
    /// 주어진 제목과 메시지로 알림창을 띄우는 함수
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - 스케줄 추가 (예시)
    
    /// 스케줄 정보를 받아 scheduleStackView에 추가하는 함수 (예시)
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
