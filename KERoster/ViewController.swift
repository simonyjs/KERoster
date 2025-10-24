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
import WidgetKit
import UniformTypeIdentifiers
import PDFKit
import CoreXLSX
import CloudKit

// SwiftSoup의 Elements 배열에 안전하게 접근 (인덱스 초과 방지)
extension Elements {
    func getOrNil(_ index: Int) -> String {
        return (self.size() > index) ? (try? self.get(index).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" : ""
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    // 🔁 CloudKit 푸시 적용 중 재업로드 방지 플래그 (KVS → Cloud 대체)
    private var isApplyingCloudPush = false   // ⬅️ 변경 (isApplyingKVS → isApplyingCloudPush)

    @IBOutlet weak var webView: WKWebView!
    @IBOutlet weak var scheduleStackView: UIStackView!

    var eventStore: EKEventStore!
    var calendarManager: CalendarManager!

    // 스케줄 데이터: 날짜별로 스케줄 배열 저장
    var schedules: [String: [[String: String]]] = [:]
    let schedulesUserDefaultsKey = "schedules"
    let ownerUserDefaultsKey = "ownerInfo"
    let totalHoursByMonthUserDefaultsKey = "totalHoursByMonth"
    var ownerInfo: String = ""
    var totalHours: String = ""

    // 저장된 이벤트 수를 추적
    var savedEventCount = 0

    // 스케줄의 고유 ID(날짜와 Activity 조합)와 캘린더 이벤트 식별자를 매핑하는 딕셔너리
    var scheduleEventMapping: [String: String] = [:]

    // 문서 피커 콜백
    private var onPickedFile: ((URL) -> Void)?

    // MARK: - 디버그 로그 함수
    func debugLog(_ message: String) {
        print("[DEBUG] \(message)")
    }

    // MARK: - 헬퍼 함수: 날짜 포맷 변환 ("yyyy-MM" 포맷)
    func formattedMonth(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - 고유 ID 생성 함수 (날짜와 Activity 값을 조합)
    func generateUniqueID(for schedule: [String: String]) -> String {
        let date = schedule["Date"] ?? ""
        let activity = schedule["Activity"] ?? ""
        return "\(date)_\(activity)"
    }

    // MARK: - UIViewController LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // 웹 델리게이트는 viewDidLoad에서 바로 설정 (SPA/iframe 대응)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // ✅ App Group 저장본 먼저 로드(초기 화면 뼈대)
        if self.schedules.isEmpty { loadSchedules() }

        // ✅ CloudKit에서 최신 스냅샷 로드
        self.loadFromCloudKit()          // ⬅️ 추가
        self.startObservingCloudKit()    // ⬅️ 추가 (푸시 구독 + 알림 수신)

        // Info.plist에서 버전과 빌드 정보 가져오기 (기존 로직 유지)
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            let versionText = "Ver. \(version) Build \(build)"
            let iconImageView = UIImageView(image: UIImage(systemName: "lightbulb.min.badge.exclamationmark.fill"))
            iconImageView.tintColor = .white
            let versionLabel = UILabel()
            versionLabel.text = versionText
            versionLabel.font = UIFont.systemFont(ofSize: 12)
            versionLabel.textColor = .white
            let containerView = UIStackView(arrangedSubviews: [iconImageView, versionLabel])
            containerView.axis = .horizontal
            containerView.spacing = 4
            containerView.alignment = .center
            containerView.sizeToFit()
            containerView.isUserInteractionEnabled = true
            containerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openInfoURL)))
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: containerView)
        }

        self.eventStore = EKEventStore()
        self.calendarManager = CalendarManager(eventStore: self.eventStore)

        // iOS 17 이상: 캘린더 접근 권한 요청 (Full Access)
        self.eventStore.requestFullAccessToEvents(completion: { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.debugLog("캘린더 접근 권한 승인됨")
                } else {
                    self.debugLog("캘린더 접근 권한 거부됨: \(error?.localizedDescription ?? "알 수 없는 오류")")
                }
            }
        })

        // 네비게이션 바 스타일 설정 (기존 유지)
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

        // 오른쪽 네비게이션 바 버튼 (스토리보드 연결이 안되어 있으면 생성)
        if navigationItem.rightBarButtonItem == nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.down.fill"),
                style: .plain,
                target: nil,
                action: nil
            )
        }

        // ===== 메뉴 액션들 (기존 유지) =====
        let importAction = UIAction(title: "Import Schedule", image: UIImage(systemName: "arrow.down.circle")) { _ in
            self.importSchedule()
        }
        let uploadXLSXAction = UIAction(title: "XLSX", image: UIImage(systemName: "tablecells")) { _ in
            let xlsx = UTType(filenameExtension: "xlsx")
            self.pickDocument(allowedTypes: [xlsx ?? .data]) { url in
                self.importRosterFromXLSX(url: url)
            }
        }
        let uploadPDFAction = UIAction(title: "PDF", image: UIImage(systemName: "doc.richtext")) { _ in
            self.pickDocument(allowedTypes: [UTType.pdf]) { url in
                self.importRosterFromPDF(url: url)
            }
        }
        let uploadMenu = UIMenu(
            title: "Upload",
            image: UIImage(systemName: "square.and.arrow.up"),
            identifier: nil,
            options: [],
            children: [uploadXLSXAction, uploadPDFAction]
        )
        let importCrewAction = UIAction(title: "Import Crew List", image: UIImage(systemName: "person.3.sequence")) { _ in
            self.importCrewList()
        }
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
                    // 오늘 이후 스케줄만 캘린더 이벤트로 추가
                    for (_, scheduleEntries) in self.schedules {
                        for entry in scheduleEntries {
                            if let startDate = self.eventStartDate(for: entry, airports: airports),
                               startDate > Date() {
                                self.addEventToCalendar(for: entry, airports: airports)
                            } else {
                                self.debugLog("스케줄이 오늘 이전이거나 시작 시간이 불명확하여 건너뜀: \(entry)")
                            }
                        }
                    }
                    let calendarName = calendar.title
                    self.showAlert(title: "Calendar export complete", message: "Saved Calendar: \(calendarName)\nTOTAL EVENT NO: \(self.savedEventCount)")
                }
            }
        }

        let menu = UIMenu(title: "Select a task", children: [importAction, uploadMenu, importCrewAction, exportAction])
        navigationItem.rightBarButtonItem?.menu = menu
    }

    deinit {
        // ⛔️ KVS 옵저버 제거 코드 삭제
        NotificationCenter.default.removeObserver(self, name: .cloudKitUpdated, object: nil) // ⬅️ 추가
    }

    // ❌ KVS 키/메서드 전부 삭제 (KVSKeys, saveToICloudKVS, loadFromICloudKVS, startObservingiCloudKVSChanges)
    // ─────────────────────────────────────────────────────────────────────
    // ⬇️ CloudKit 동기화 메서드 추가
    // MARK: - CloudKit 저장
    private func saveToCloudKit() {
        // App Group 미러(위젯) 유지
        if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
            shared.set(self.ownerInfo, forKey: self.ownerUserDefaultsKey)
            let monthlyStd = UserDefaults.standard.dictionary(forKey: self.totalHoursByMonthUserDefaultsKey) as? [String: String] ?? [:]
            shared.set(monthlyStd, forKey: self.totalHoursByMonthUserDefaultsKey)
            shared.synchronize()
        }

        let monthlyStd = UserDefaults.standard.dictionary(forKey: self.totalHoursByMonthUserDefaultsKey) as? [String: String] ?? [:]
        let state = CloudState(
            schedules: self.schedules,
            ownerInfo: self.ownerInfo,
            totalHoursByMonth: monthlyStd,
            updatedAt: Date()
        )
        CloudKitManager.shared.save(state: state) { result in
            switch result {
            case .success:
                self.debugLog("CloudKit 저장 완료")
                DispatchQueue.main.async { WidgetCenter.shared.reloadAllTimelines() }
            case .failure(let err):
                self.debugLog("CloudKit 저장 실패: \(err.localizedDescription)")
            }
        }
    }

    // MARK: - CloudKit 로드
    private func loadFromCloudKit() {
        CloudKitManager.shared.fetch { result in
            switch result {
            case .success(let maybe):
                guard let remote = maybe else {
                    self.debugLog("CloudKit에 아직 데이터 없음")
                    return
                }
                DispatchQueue.main.async {
                    self.isApplyingCloudPush = true
                    self.schedules = remote.schedules
                    self.ownerInfo = remote.ownerInfo
                    UserDefaults.standard.set(remote.totalHoursByMonth, forKey: self.totalHoursByMonthUserDefaultsKey)

                    // App Group 미러
                    if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
                        shared.set(self.ownerInfo, forKey: self.ownerUserDefaultsKey)
                        shared.set(remote.totalHoursByMonth, forKey: self.totalHoursByMonthUserDefaultsKey)
                        shared.synchronize()
                    }

                    self.totalHours = remote.totalHoursByMonth.values.first ?? self.totalHours
                    self.saveSchedules(mirrorToCloud: false) // ⬅️ 로컬 저장만 (재업로드 방지)
                    self.printSchedulesToConsole()
                    WidgetCenter.shared.reloadAllTimelines()
                    self.isApplyingCloudPush = false
                }
            case .failure(let err):
                self.debugLog("CloudKit 로드 실패: \(err.localizedDescription)")
            }
        }
    }

    // MARK: - CloudKit 변경 구독/수신
    private func startObservingCloudKit() {
        CloudKitManager.shared.subscribeIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(onCloudKitUpdate),
                                               name: .cloudKitUpdated, object: nil)
    }

    @objc private func onCloudKitUpdate() {
        guard !self.isApplyingCloudPush else { return }
        self.loadFromCloudKit()
    }
    // ─────────────────────────────────────────────────────────────────────

    // MARK: - 이하 기존 코드(웹, 달력, 파서, 임포트 등)는 그대로 유지
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 첫 진입 시 페이지 로드
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
    }

    // WebView, UserDefaults loadSchedules(), importSchedule(), importCrewList(), XLSX/PDF 파서,
    // 캘린더 이벤트 관련 모든 메서드들은 네가 올린 그대로 유지하면 돼.

    // 🔁 여기 “saveSchedules”만 CloudKit 반영하도록 수정
    // MARK: - UserDefaults 관련 (스케줄 저장/불러오기)
    func saveSchedules(mirrorToCloud: Bool = true) {   // ⬅️ 시그니처 변경 (mirrorToKVS → mirrorToCloud)
        if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
            do {
                let data = try JSONEncoder().encode(schedules)
                sharedDefaults.set(data, forKey: schedulesUserDefaultsKey)
                sharedDefaults.synchronize()
                print("스케줄 저장 성공 (App Group)")

                // CloudKit 업로드 (푸시 적용 중에는 재업로드 방지)
                if mirrorToCloud && !isApplyingCloudPush {
                    self.saveToCloudKit()
                }
            } catch {
                print("스케줄 저장 실패: \(error)")
            }
        } else {
            print("공유 UserDefaults 생성 실패")
        }
    }

    func loadSchedules() {
        if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
           let data = sharedDefaults.data(forKey: schedulesUserDefaultsKey) {
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
    
    // URL 이동
    @objc private func openInfoURL() {
        let raw = UserDefaults.standard.string(forKey: "savedURL")
        ?? "https://pinnate-century-46a.notion.site/KERoster-1973143fe5db80588f62d8959e7c0fcc?pvs=74"
        
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s } // 스킴 보정
        
        guard let url = URL(string: s) else { return }
        
        if #available(iOS 10.0, *) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            UIApplication.shared.openURL(url)
        }
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
        if let calendarVC = storyboard.instantiateViewController(withIdentifier: "ZoomableCalendarContainerViewController") as? ZoomableCalendarContainerViewController {
            calendarVC.schedules = schedules
            calendarVC.ownerInfo = self.ownerInfo
            calendarVC.totalHours = self.totalHours
            navigationController?.pushViewController(calendarVC, animated: true)
        }
    }
    
    @IBAction func CrewButtonTapped(_ sender: UIBarButtonItem) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        if let vc = sb.instantiateViewController(withIdentifier: "CrewListByMonthViewController") as? CrewListByMonthViewController {
            vc.schedules = schedules  // 전달
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
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
    
    // MARK: - 새 레이아웃(Flight/Activity, STD, STA) → dd-MMM-yyyy & HH:mm 분리
    private func splitISODateTime(_ dt: String) -> (dateStr: String, timeStr: String)? {
        let s = dt.trimmingCharacters(in: .whitespacesAndNewlines)
        // 허용: "yyyy-MM-dd HH:mm" , "dd-MMM-yyyy HH:mm"
        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "yyyy-MM-dd HH:mm"
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.dateFormat = "dd-MMM-yyyy HH:mm"
        
        let outDate = DateFormatter()
        outDate.locale = Locale(identifier: "en_US_POSIX")
        outDate.dateFormat = "dd-MMM-yyyy"
        
        let outTime = DateFormatter()
        outTime.locale = Locale(identifier: "en_US_POSIX")
        outTime.dateFormat = "HH:mm"
        
        var d: Date? = f1.date(from: s)
        if d == nil { d = f2.date(from: s) }
        guard let date = d else { return nil }
        return (outDate.string(from: date), outTime.string(from: date))
    }
    
    // MARK: - Crew 병합(중복시 필드 보강) 유틸
    private func mergeCrewRow(_ row: [String:String], into entry: inout [String:String]) {
        let hasValue = row.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !hasValue { return }
        // 현재 리스트 로드
        var list: [[String:String]] = []
        if let json = entry["CrewList"], let data = json.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String:String]] {
            list = arr
        }
        
        func merge(into base: inout [String:String], with add: [String:String]) {
            for (k, v) in add {
                let vv = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if vv.isEmpty { continue }
                if (base[k]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    base[k] = vv
                }
            }
        }
        
        // 중복 탐지: CrewID 우선, 없으면 Name
        if let id = row["CrewID"], !id.isEmpty, let idx = list.firstIndex(where: { ($0["CrewID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == id }) {
            var base = list[idx]
            merge(into: &base, with: row)
            list[idx] = base
        } else if let nm = row["Name"], !nm.isEmpty, let idx = list.firstIndex(where: { ($0["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == nm }) {
            var base = list[idx]
            merge(into: &base, with: row)
            list[idx] = base
        } else {
            list.append(row)
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: list, options: []),
           let json = String(data: data, encoding: .utf8) {
            entry["CrewList"] = json
        }
    }
    
    // MARK: - 스케줄 파싱 및 가져오기 (새 레이아웃 우선, 실패 시 구형 레이아웃 폴백)
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
                
                // ─────────────────────────────────────────────────────────────
                // 1) 새 레이아웃 시도
                // ─────────────────────────────────────────────────────────────
                var newExtracted: [String: [[String: String]]] = [:]  // depDate → [entries]
                var newDepMonthCount: [String: Int] = [:]
                var seqCountersByDate: [String: Int] = [:]
                var indexMap: [String: (dateKey: String, idx: Int)] = [:] // flightKey → 위치
                var ownerFromNew = ""
                var hoursFromNew = ""
                var parsedByNewLayout = false
                
                // 현재 편 컨텍스트(빈 비행 행이 이어질 때 사용)
                var currentPos: (dateKey: String, idx: Int)? = nil
                
                func flightKey(item: String, depDate: String, depAp: String, depTime: String) -> String {
                    return "\(depDate)|\(item)|\(depAp)|\(depTime)"
                }
                
                do {
                    // 상단 Owner/Hours 추정 추출 (새 레이아웃에서 텍스트 블럭 탐색)
                    for td in try doc.select("td") {
                        let t = try td.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if ownerFromNew.isEmpty, t.contains("|"), t.range(of: #"\d"#, options: .regularExpression) != nil, t.count < 100 {
                            ownerFromNew = t
                        }
                        if hoursFromNew.isEmpty, t.hasPrefix("FLY "), t.contains("TVL ") {
                            hoursFromNew = t
                        }
                        if !ownerFromNew.isEmpty, !hoursFromNew.isEmpty { break }
                    }
                    
                    // 본문 테이블 탐색
                    let allRows = try doc.select("tr")
                    var readMode = false
                    
                    for row in allRows {
                        let tds = try row.select("td")
                        if tds.isEmpty { continue }
                        
                        // 헤더 감지
                        let headerTexts = try tds.array().map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                        if headerTexts.contains("Flight/Activity") && headerTexts.contains("STD") && headerTexts.contains("STA") {
                            readMode = true
                            parsedByNewLayout = true
                            continue
                        }
                        if !readMode { continue }
                        
                        func cell(_ i: Int) -> String { tds.getOrNil(i) }
                        
                        // 0:'', 1:Flight/Activity, 2:From, 3:STD, 4:To, 5:STA, 6:A/C, 7:Acting rank,
                        // 8:Duty(WT), 9:PIC code, 10:Crew ID, 11:Name, 12:Comment, 13:Special Duty Code, 14:''
                        let rawItem = cell(1).trimmingCharacters(in: .whitespaces)
                        let depAp = cell(2)
                        let stdRaw = cell(3)
                        let arrAp = cell(4)
                        let staRaw = cell(5)
                        let ac = cell(6)
                        let actingRank = cell(7)
                        let dutyRaw = cell(8).trimmingCharacters(in: .whitespaces) // WT
                        let picCode = cell(9)
                        let crewID = cell(10)
                        let crewName = cell(11)
                        let comment = cell(12)
                        let sdcPerCrew = cell(13)
                        
                        // Deadhead 교정: DH1234 → item=KE1234, WT=TVL(강제)
                        var item = rawItem
                        var isDH = false
                        if let r = rawItem.range(of: #"^DH\s*(\d{3,4}[A-Z]?)$"#, options: .regularExpression) {
                            let tail = String(rawItem[r]).replacingOccurrences(of: "DH", with: "").trimmingCharacters(in: .whitespaces)
                            item = "KE\(tail)"
                            isDH = true
                        }
                        
                        // WT 확정: WT가 있으면 저장, 없으면 "" (단, DH면 TVL 강제)
                        var workTypeFromWT = dutyRaw.isEmpty ? "" : dutyRaw.uppercased()
                        if isDH { workTypeFromWT = "TVL" }
                        
                        // 크루 칼럼 중 하나라도 값이 있으면 "크루 내용 있음"
                        let hasCrew = [actingRank, dutyRaw, picCode, crewID, crewName, comment, sdcPerCrew]
                            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        
                        // 새 비행편 시작 행인지 판별
                        let isNewFlightRow: Bool = {
                            let bits = [rawItem, depAp, stdRaw, arrAp, staRaw].map { !$0.isEmpty }
                            return bits.filter { $0 }.count >= 3
                        }()
                        
                        if isNewFlightRow {
                            // 시간 파싱
                            guard let dep = self.splitISODateTime(stdRaw),
                                  let arr = self.splitISODateTime(staRaw) else {
                                self.debugLog("STD/STA 파싱 실패: \(stdRaw) / \(staRaw)")
                                continue
                            }
                            let depDate = dep.dateStr
                            let depTime = dep.timeStr
                            let arrDate = arr.dateStr
                            let arrTime = arr.timeStr
                            
                            // UTC 문자열
                            let depUTC = self.convertLocalTimeToUTCTime(dateString: depDate, timeString: depTime, airportCode: depAp, airports: airports)
                            let arrUTC = self.convertLocalTimeToUTCTime(dateString: arrDate, timeString: arrTime, airportCode: arrAp, airports: airports)
                            
                            // 월 카운트
                            let ddf = DateFormatter()
                            ddf.locale = Locale(identifier: "en_US_POSIX")
                            ddf.dateFormat = "dd-MMM-yyyy"
                            if let d = ddf.date(from: depDate) {
                                let mKey = self.formattedMonth(for: d)
                                newDepMonthCount[mKey, default: 0] += 1
                            }
                            
                            // 키
                            let fKey = flightKey(item: item, depDate: depDate, depAp: depAp, depTime: depTime)
                            
                            // 신규/기존 분기
                            if let existingPos = indexMap[fKey] {
                                var arrForDate = newExtracted[existingPos.dateKey] ?? []
                                var entry = arrForDate[existingPos.idx]
                                if entry["AC"]?.isEmpty ?? true, !ac.isEmpty { entry["AC"] = ac }
                                if entry["ActingRank"]?.isEmpty ?? true, !actingRank.isEmpty { entry["ActingRank"] = actingRank }
                                if (entry["WorkType"]?.isEmpty ?? true), !workTypeFromWT.isEmpty { entry["WorkType"] = workTypeFromWT }
                                if (entry["Activity"]?.isEmpty ?? true) { entry["Activity"] = item }
                                if (entry["Item"]?.isEmpty ?? true) { entry["Item"] = item }
                                if hasCrew {
                                    let crewRow: [String:String] = [
                                        "ActingRank": actingRank,
                                        "Duty": dutyRaw,
                                        "PICCode": picCode,
                                        "CrewID": crewID,
                                        "Name": crewName,
                                        "Comment": comment,
                                        "SDC": sdcPerCrew
                                    ]
                                    self.mergeCrewRow(crewRow, into: &entry)
                                }
                                arrForDate[existingPos.idx] = entry
                                newExtracted[existingPos.dateKey] = arrForDate
                                currentPos = existingPos
                            } else {
                                let seq = (seqCountersByDate[depDate] ?? 0) + 1
                                seqCountersByDate[depDate] = seq
                                
                                var entry: [String:String] = [
                                    "Seq": "\(seq)",
                                    "Activity": item,                 // 비행은 item(KE####)
                                    "Item": item,
                                    "WorkType": workTypeFromWT,       // WT 없으면 "", DH면 TVL
                                    "DutyReport": "",
                                    "DepAp": depAp,
                                    "DepStnTime": depTime,
                                    "DepStnTimeOpt": "",
                                    "DepDate": depDate,
                                    "ArrAp": arrAp,
                                    "ArrStnTime": arrTime,
                                    "ArrStnTimeOpt": "",
                                    "ArrDate": arrDate,
                                    "DutyDebrief": "",
                                    "DutyDebriefTime": "",
                                    "DutyDebriefDate": arrDate,
                                    "FlyingHours": "",
                                    "DutyHours": "",
                                    "SDC": "",
                                    "Hotel": "",
                                    "DepStnTimeUTC": depUTC,
                                    "ArrStnTimeUTC": arrUTC,
                                    "Date": depDate
                                ]
                                if !ac.isEmpty        { entry["AC"] = ac }
                                if !actingRank.isEmpty { entry["ActingRank"] = actingRank }
                                
                                if hasCrew {
                                    let crewRow: [String:String] = [
                                        "ActingRank": actingRank,
                                        "Duty": dutyRaw,
                                        "PICCode": picCode,
                                        "CrewID": crewID,
                                        "Name": crewName,
                                        "Comment": comment,
                                        "SDC": sdcPerCrew
                                    ]
                                    self.mergeCrewRow(crewRow, into: &entry)
                                }
                                
                                var arrForDate = newExtracted[depDate] ?? []
                                arrForDate.append(entry)
                                newExtracted[depDate] = arrForDate
                                let pos = (dateKey: depDate, idx: arrForDate.count - 1)
                                indexMap[fKey] = pos
                                currentPos = pos
                                self.debugLog("추출 스케줄(새 형식 신규): \(entry)")
                            }
                            continue
                        }
                        
                        // 여기부터는 "새 비행 정보 없이 크루만 있는 연속 행" 처리
                        if hasCrew, let pos = currentPos {
                            var arrForDate = newExtracted[pos.dateKey] ?? []
                            guard pos.idx >= 0 && pos.idx < arrForDate.count else {
                                self.debugLog("currentPos out of range. resetting context.")
                                currentPos = nil
                                continue
                            }
                            
                            var entry = arrForDate[pos.idx]
                            if (entry["AC"]?.isEmpty ?? true), !ac.isEmpty { entry["AC"] = ac }
                            if (entry["ActingRank"]?.isEmpty ?? true), !actingRank.isEmpty { entry["ActingRank"] = actingRank }
                            if (entry["WorkType"]?.isEmpty ?? true), !workTypeFromWT.isEmpty { entry["WorkType"] = workTypeFromWT }
                            if hasCrew {
                                let crewRow: [String:String] = [
                                    "ActingRank": actingRank,
                                    "Duty": dutyRaw,
                                    "PICCode": picCode,
                                    "CrewID": crewID,
                                    "Name": crewName,
                                    "Comment": comment,
                                    "SDC": sdcPerCrew
                                ]
                                self.mergeCrewRow(crewRow, into: &entry)
                            }
                            arrForDate[pos.idx] = entry
                            newExtracted[pos.dateKey] = arrForDate
                            continue
                        }
                    }
                }
                
                if parsedByNewLayout, !newExtracted.isEmpty {
                    // 새 레이아웃 성공: 저장/병합 (월 갈아끼우기)
                    DispatchQueue.main.async {
                        if !ownerFromNew.isEmpty { self.ownerInfo = ownerFromNew }
                        if !hoursFromNew.isEmpty { self.totalHours = hoursFromNew }
                        UserDefaults.standard.set(self.ownerInfo, forKey: self.ownerUserDefaultsKey)
                        
                        if let maxEntry = newDepMonthCount.max(by: { $0.value < $1.value }) {
                            let majorityMonthKey = maxEntry.key
                            self.debugLog("출발 스케줄이 가장 많은 달(새 형식): \(majorityMonthKey)")
                            var monthlyStd = UserDefaults.standard.dictionary(forKey: self.totalHoursByMonthUserDefaultsKey) as? [String: String] ?? [:]
                            monthlyStd[majorityMonthKey] = self.totalHours
                            UserDefaults.standard.set(monthlyStd, forKey: self.totalHoursByMonthUserDefaultsKey)
                            self.totalHours = monthlyStd[majorityMonthKey] ?? self.totalHours
                            
                            // 해당 월의 기존 스케줄 삭제
                            let df = DateFormatter()
                            df.locale = Locale(identifier: "en_US_POSIX")
                            df.dateFormat = "dd-MMM-yyyy"
                            let keysToRemove = self.schedules.keys.filter { key in
                                if let dateObj = df.date(from: key) {
                                    return self.formattedMonth(for: dateObj) == majorityMonthKey
                                }
                                return false
                            }
                            for key in keysToRemove { self.schedules.removeValue(forKey: key) }
                        }
                        
                        // 새 데이터 덮어쓰기
                        for (k, v) in newExtracted { self.schedules[k] = v }
                        
                        self.saveSchedules()
                        self.printSchedulesToConsole()
                        self.showAlert(title: "Import Complete", message: "The schedule was successfully imported (new layout + full crew).")
                    }
                    return
                }
                
                // ─────────────────────────────────────────────────────────────
                // 2) 구형 레이아웃 폴백 (기존 파서)
                // ─────────────────────────────────────────────────────────────
                
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
                
                // 소유자 정보 추출(구형)
                do {
                    if let ownerElement = try doc.select("body > table > tbody > tr > td:nth-child(2) > table:nth-child(2) > tbody > tr:nth-child(3) > td:nth-child(4) > p > span").first() {
                        let fullOwnerText = try ownerElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if let pipeRange = fullOwnerText.range(of: "|") {
                            self.ownerInfo = String(fullOwnerText[..<pipeRange.lowerBound])
                        } else {
                            self.ownerInfo = fullOwnerText
                        }
                        self.debugLog("소유자 정보 추출 성공(구형): \(self.ownerInfo)")
                    } else {
                        self.debugLog("소유자 정보를 찾을 수 없습니다.(구형)")
                    }
                } catch {
                    self.debugLog("소유자 정보 추출 중 오류 발생(구형): \(error)")
                }
                
                // 총 시간 정보 추출(구형)
                do {
                    if let hoursElement = try doc.select("body > table > tbody > tr > td:nth-child(2) > table:nth-child(2) > tbody > tr:nth-child(3) > td:nth-child(5) > p > span").first() {
                        self.totalHours = try hoursElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        self.debugLog("총 시간 정보 추출 성공(구형): \(self.totalHours)")
                    } else {
                        self.debugLog("총 시간 정보를 찾을 수 없습니다.(구형)")
                    }
                } catch {
                    self.debugLog("총 시간 정보 추출 중 오류 발생(구형): \(error)")
                }
                
                UserDefaults.standard.set(self.ownerInfo, forKey: self.ownerUserDefaultsKey)
                
                var depMonthCount: [String: Int] = [:]
                
                // 스케줄 파싱(구형)
                for (_, row) in rows.enumerated() {
                    let columns: Elements = try row.select("td")
                    
                    if columns.size() > 10, !(try columns[1].text().contains("Date")) {
                        var missingFields = [String]()
                        
                        var date = columns.getOrNil(1)
                        let activity = columns.getOrNil(2)     // 원문 Activity
                        let dutyReport = columns.getOrNil(3)
                        let item = columns.getOrNil(4)
                        let workType = columns.getOrNil(6)     // WT
                        let depStationTimeFull = columns.getOrNil(8)
                        let arrStationTimeFull = columns.getOrNil(9)
                        let dutyDebrief = columns.getOrNil(11)
                        let flyingHours = columns.getOrNil(12)
                        let dutyHours = columns.getOrNil(13)
                        let sdc = columns.getOrNil(14)
                        let hotel = columns.getOrNil(16)
                        
                        if date.isEmpty {
                            if lastDate == "Unknown" {
                                self.debugLog("날짜 정보 누락: 이전 날짜 정보도 없음")
                                continue
                            }
                            date = lastDate
                        } else {
                            lastDate = date
                        }
                        
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
                        
                        if !missingFields.isEmpty {
                            self.debugLog("이벤트 변환 실패 - 누락된 필드: \(missingFields.joined(separator: ", ")) (행: \(try columns.text()))")
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
                            "Activity": activity,                // 원문 Activity 유지(RESERVE 등)
                            "Item": item.isEmpty ? activity : item,
                            "WorkType": workType,                // WT가 비면 비워둠
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
                        self.debugLog("추출된 스케줄(구형): \(scheduleEntry)")
                        
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
                
                // ★ 덮어쓰기 방식: 기존 스케줄 데이터를 임포트된 데이터에 해당하는 날짜만 업데이트
                DispatchQueue.main.async {
                    if let maxEntry = depMonthCount.max(by: { $0.value < $1.value }) {
                        let majorityMonthKey = maxEntry.key
                        self.debugLog("출발 스케줄이 가장 많은 달(구형): \(majorityMonthKey)")
                        var monthlyStd = UserDefaults.standard.dictionary(forKey: self.totalHoursByMonthUserDefaultsKey) as? [String: String] ?? [:]
                        monthlyStd[majorityMonthKey] = self.totalHours
                        UserDefaults.standard.set(monthlyStd, forKey: self.totalHoursByMonthUserDefaultsKey)
                        self.totalHours = monthlyStd[majorityMonthKey] ?? ""
                        
                        let dateFormatterForKey = DateFormatter()
                        dateFormatterForKey.dateFormat = "dd-MMM-yyyy"
                        dateFormatterForKey.locale = Locale(identifier: "en_US_POSIX")
                        let keysToRemove = self.schedules.keys.filter { key in
                            if let dateObj = dateFormatterForKey.date(from: key) {
                                return self.formattedMonth(for: dateObj) == majorityMonthKey
                            }
                            return false
                        }
                        for key in keysToRemove {
                            self.schedules.removeValue(forKey: key)
                        }
                    }
                    
                    for (date, newEntries) in extractedSchedules {
                        self.schedules[date] = newEntries
                    }
                    
                    self.saveSchedules()
                    self.printSchedulesToConsole()
                    self.showAlert(title: "Import Complete", message: "The schedule was successfully imported (legacy layout).")
                }
                
            } catch {
                self.debugLog("HTML 파싱 오류: \(error)")
                DispatchQueue.main.async {
                    self.showAlert(title: "Import Fail", message: "Failed to Import schedule.(HTML parsing error)")
                }
            }
        }
    }
    
    // ✅ 유지: 팝업 방식 크루리스트 임포트
    private func extractIATAs(from route: String) -> (String?, String?) {
        // 예) "ICN-LAX", "ICN → LAX", "ICN / LAX"
        let pattern = #"([A-Z]{3})\s*[-→/>\s]+\s*([A-Z]{3})"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(route.startIndex..., in: route)
            if let m = regex.firstMatch(in: route, options: [], range: range) {
                let dep = Range(m.range(at: 1), in: route).map { String(route[$0]) }
                let arr = Range(m.range(at: 2), in: route).map { String(route[$0]) }
                return (dep, arr)
            }
        }
        return (nil, nil)
    }
    
    // MARK: - ✅ 크루리스트: 편명 숫자 + 날짜(DepDate 우선, Date 폴백) + 출발지(있으면) 매칭 (팝업 버전 유지)
    func importCrewList() {
        let targetWebView: WKWebView = self.webView
        
        targetWebView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self] (html: Any?, error: Error?) in
            guard let self = self else { return }
            
            if let error = error {
                self.debugLog("CrewList JS 실행 오류: \(error)")
                self.showAlert(title: "Import Fail", message: "Failed to read HTML.")
                return
            }
            guard let htmlString = html as? String else {
                self.debugLog("CrewList HTML 추출 실패")
                self.showAlert(title: "Import Fail", message: "HTML was empty.")
                return
            }
            
            do {
                let doc = try SwiftSoup.parse(htmlString)
                
                // 팝업 상단 정보
                let flightCode = try doc.select("#crewListDialog .flight_info .flight_code")
                    .first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let popupDateString = try doc.select("#crewListDialog .flight_info .date")
                    .first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let routeText = try doc.select("#crewListDialog .flight_info .route")
                    .first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let (popupDepIATA, _) = self.extractIATAs(from: routeText)
                
                let depDateFromPopup = self.normalizePopupDate(popupDateString) ?? ""
                
                // 필수값 확인
                if flightCode.isEmpty || depDateFromPopup.isEmpty {
                    self.showAlert(title: "Import Fail", message: "Missing flight code or date in popup.")
                    return
                }
                
                // 테이블 파싱 (9 컬럼)
                let rows = try doc.select("#crewListDialog table.plain_table tbody tr")
                var crewArray: [[String: String]] = []
                func clean(_ s: String) -> String {
                    s.replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\t", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                for row in rows {
                    let tds = try row.select("td")
                    if tds.count >= 9 {
                        crewArray.append([
                            "Name": clean(try tds[0].text()),
                            "CrewID": clean(try tds[1].text()),
                            "WorkType": clean(try tds[2].text()),
                            "PostingRank": clean(try tds[3].text()),
                            "PICCode": clean(try tds[4].text()),
                            "CheckedIn": clean(try tds[5].text()),
                            "Contact": clean(try tds[6].text()),
                            "Role": clean(try tds[7].text()),
                            "SDC": clean(try tds[8].text())
                        ])
                    }
                }
                
                guard !crewArray.isEmpty else {
                    self.showAlert(title: "No Data", message: "No crew rows were found.")
                    return
                }
                
                // 매칭 준비
                let crewNum = self.normalizeItemNumber(flightCode)
                self.debugLog("CrewImport try | flightCode=\(flightCode) num=\(crewNum) popupDate=\(depDateFromPopup) popupDep=\(popupDepIATA ?? "nil")")
                
                // 후보 엔트리(전 스케줄 탐색): DepDate == 팝업 OR Date == 팝업
                struct EntryRef { let keyDate: String; let index: Int }
                var refs: [EntryRef] = []
                for (keyDate, entries) in self.schedules {
                    for (idx, e) in entries.enumerated() {
                        let depDateInEntry = e["DepDate"] ?? ""
                        let dateInEntry    = e["Date"] ?? ""
                        if depDateInEntry == depDateFromPopup || dateInEntry == depDateFromPopup {
                            refs.append(EntryRef(keyDate: keyDate, index: idx))
                        }
                    }
                }
                
                guard !refs.isEmpty else {
                    self.showAlert(title: "Not Saved", message: "No schedules on \(depDateFromPopup) (searched by DepDate/Date).")
                    return
                }
                
                var matched = false
                var strictMatched = false
                
                for ref in refs {
                    guard var entry = self.schedules[ref.keyDate]?[ref.index] else { continue }
                    
                    let wt = entry["WorkType"] ?? ""
                    guard wt == "FLY" || wt == "TVL" else { continue }
                    
                    let itemRaw = entry["Item"] ?? ""
                    let itemNum = self.normalizeItemNumber(itemRaw)
                    
                    let depDateInEntry = entry["DepDate"] ?? ""
                    let dateInEntry    = entry["Date"] ?? ""
                    let entryDepAp     = entry["DepAp"] ?? ""
                    
                    // 팝업 출발 IATA가 있으면 함께 체크
                    if let popDep = popupDepIATA, !popDep.isEmpty, entryDepAp != popDep { continue }
                    
                    // 1차: 편명 숫자 + DepDate == 팝업 날짜
                    if itemNum == crewNum && depDateInEntry == depDateFromPopup {
                        if let data = try? JSONSerialization.data(withJSONObject: crewArray, options: []),
                           let jsonString = String(data: data, encoding: .utf8) {
                            entry["CrewList"] = jsonString
                            self.schedules[ref.keyDate]![ref.index] = entry
                            matched = true
                            strictMatched = true
                            self.debugLog("✅ CrewList STRICT saved to \(itemRaw) | bucket=\(ref.keyDate) DepDate=\(depDateInEntry) == Popup=\(depDateFromPopup)")
                        }
                        continue
                    }
                    
                    // 2차(폴백): 편명 숫자 + Date == 팝업 날짜
                    if itemNum == crewNum && dateInEntry == depDateFromPopup {
                        if let data = try? JSONSerialization.data(withJSONObject: crewArray, options: []),
                           let jsonString = String(data: data, encoding: .utf8) {
                            entry["CrewList"] = jsonString
                            self.schedules[ref.keyDate]![ref.index] = entry
                            matched = true
                            self.debugLog("⬇️ CrewList FALLBACK saved to \(itemRaw) | bucket=\(ref.keyDate) entry.Date=\(dateInEntry) == Popup=\(depDateFromPopup), DepDate=\(depDateInEntry)")
                        }
                    }
                }
                
                if matched {
                    self.saveSchedules()
                    let mode = strictMatched ? "strict" : "fallback"
                    self.showAlert(title: "Crew List Imported", message: "Saved on \(depDateFromPopup) (\(mode)).")
                } else {
                    self.showAlert(title: "Not Saved",
                                   message: "No matching schedule (flight number/date/route). Check (+1)/(-1) cases.")
                }
                
            } catch {
                self.debugLog("CrewList 파싱 실패: \(error)")
                self.showAlert(title: "Import Fail", message: "Failed to parse Crew List.")
            }
        }
    }
    
    // MARK: - CrewList 보조: 항공편 코드 숫자 정규화 (앞 2글자 제외 + 숫자만)
    private func normalizeItemNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 3 {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: 2)
            let suffix = String(trimmed[idx...])
            return suffix.filter { $0.isNumber }
        } else {
            return trimmed.filter { $0.isNumber }
        }
    }
    
    // MARK: - CrewList 보조: 팝업 날짜문자열 보정 ("29 Aug 25"/"29 Aug 2025" -> "dd-MMM-yyyy")
    private func normalizePopupDate(_ popupDate: String) -> String? {
        let from = DateFormatter()
        from.locale = Locale(identifier: "en_US_POSIX")
        from.dateFormat = "dd MMM yy"
        let to = DateFormatter()
        to.locale = Locale(identifier: "en_US_POSIX")
        to.dateFormat = "dd-MMM-yyyy"
        if let d = from.date(from: popupDate) { return to.string(from: d) }
        from.dateFormat = "dd MMM yyyy"
        if let d = from.date(from: popupDate) { return to.string(from: d) }
        return nil
    }
    
    // MARK: - 헬퍼 함수: 스케줄의 시작 시간을 Date 객체로 반환 (FLY/TVL는 DepStnTime, 그 외는 DutyReport 사용)
    func eventStartDate(for entry: [String: String], airports: [[String: Any]]) -> Date? {
        let workType = entry["WorkType"] ?? ""
        if workType == "FLY" || workType == "TVL" {
            guard let depDateString = entry["DepDate"],
                  let depStnTime = entry["DepStnTime"],
                  let depAp = entry["DepAp"],
                  let depTimeZone = timeZoneForAirport(iata: depAp, airports: airports)
            else { return nil }
            return dateFromLocal(dateString: depDateString, timeString: depStnTime, timeZone: depTimeZone)
        } else {
            guard let depDateString = entry["DepDate"],
                  let dutyReport = entry["DutyReport"],
                  let depAp = entry["DepAp"],
                  let startTimeZone = timeZoneForAirport(iata: depAp, airports: airports)
            else { return nil }
            return dateFromLocal(dateString: depDateString, timeString: dutyReport, timeZone: startTimeZone)
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
    
    // MARK: - 캘린더 이벤트 추가 함수 (중복 검사 및 노트 업데이트 포함)
    func addEventToCalendar(for scheduleEntry: [String: String], airports: [[String: Any]]?) {
        let koreanTimeZone = TimeZone(identifier: "Asia/Seoul")!
        let workType = scheduleEntry["WorkType"] ?? ""
        
        var eventTitle: String = ""
        var startDate: Date?
        var endDate: Date?
        var eventTimeZone: TimeZone = koreanTimeZone
        var noteText: String = ""
        
        // 새로 추가하는 스케줄의 고유 ID (Date와 Activity 조합)
        let uniqueID = generateUniqueID(for: scheduleEntry)
        
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
            
            var modifiedItem = item
            if workType == "TVL" {
                if item.count >= 2 {
                    modifiedItem = "DH" + item.dropFirst(2)
                } else {
                    modifiedItem = "DH" + item
                }
            }
            
            // 기본 제목 생성 및 타임존, 날짜 변환
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
            
            // 기본 노트 생성 (TVL인 경우 "Deadhead" 추가)
            let baseNote = generateBaseNote(for: scheduleEntry,
                                            workType: workType,
                                            modifiedItem: modifiedItem,
                                            depStnTime: depStnTime,
                                            depAp: depAp,
                                            arrAp: arrAp,
                                            arrStnTime: arrStnTime)
            eventTitle = baseTitle
            noteText = baseNote
            
            // 동일 시간 범위에서 제목이 같은 이벤트를 중복으로 간주
            if let start = startDate, let end = endDate, let selectedCal = calendarManager.selectedCalendar {
                let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [selectedCal])
                let existingEvents = eventStore.events(matching: predicate)
                if let dup = existingEvents.first(where: { $0.title == baseTitle }) {
                    self.debugLog("⚠️ 중복 일정 발견! 기존 이벤트의 노트 업데이트: \(baseTitle)")
                    updateEventNotes(dup, with: scheduleEntry)
                    return
                }
            }
            
            self.debugLog("최종 noteText (비행 듀티): \(noteText)")
            
        } else {
            // 그라운드 듀티 이벤트 처리
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
            guard let startTimeZone = timeZoneForAirport(iata: depAp, airports: airports ?? []),
                  let start = dateFromLocal(dateString: depDateString, timeString: dutyReport, timeZone: startTimeZone) else {
                self.debugLog("그라운드 듀티 시작 시간 변환 실패 for DepAp: \(depAp), DepDate: \(depDateString), DutyReport: \(dutyReport)")
                return
            }
            guard let endTimeZone = timeZoneForAirport(iata: arrAp, airports: airports ?? []),
                  let end = dateFromLocal(dateString: dutyDebriefDate, timeString: dutyDebriefTime, timeZone: endTimeZone) else {
                self.debugLog("그라운드 듀티 종료 시간 변환 실패 for ArrAp: \(arrAp), DutyDebriefDate: \(dutyDebriefDate), DutyDebriefTime: \(dutyDebriefTime)")
                return
            }
            startDate = start
            endDate = end
            eventTimeZone = startTimeZone
            self.debugLog("그라운드 듀티 이벤트 변환 성공: \(baseTitle)")
            
            var baseNote = baseTitle
            if let sdc = scheduleEntry["SDC"], !sdc.isEmpty {
                baseNote += "\nSDC: \(sdc)"
            }
            noteText = baseNote
        }
        
        guard let start = startDate, let end = endDate else { return }
        
        let event = EKEvent(eventStore: self.eventStore)
        event.title = eventTitle
        
        // “KEROSTER” 노트에 줄바꿈 추가.
        var finalNotes = "KEROSTER\n" + noteText
        
        // 크루정보가 있으면 분리선 후 추가
        if let crewNote = buildCrewNote(from: scheduleEntry) {
            finalNotes += "\n----\n" + crewNote
        }
        
        event.notes = finalNotes
        event.startDate = start
        event.endDate = end
        event.timeZone = eventTimeZone
        
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
                // 이벤트 저장 성공 시, 고유 ID와 이벤트 식별자 매핑 업데이트
                self.scheduleEventMapping[uniqueID] = event.eventIdentifier
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
    
    // MARK: - 헬퍼 함수: 로컬 시간 → UTC 시간 문자열
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
    
    // MARK: - 헬퍼 함수: 기존 이벤트의 Notes 업데이트 (변경 사항만 추가)
    func updateEventNotes(_ event: EKEvent, with entry: [String: String]) {
        let updatedSection = generateUpdatedInfo(for: entry)
        let marker = "\n----\n"
        
        var currentNotes = event.notes ?? ""
        
        if let markerRange = currentNotes.range(of: marker) {
            currentNotes = String(currentNotes[..<markerRange.upperBound]) + updatedSection
        } else {
            currentNotes += marker + updatedSection
        }
        
        event.notes = currentNotes
        do {
            try eventStore.save(event, span: .thisEvent)
            debugLog("✅ 기존 일정의 노트에 변경 사항 업데이트 완료")
        } catch {
            debugLog("❌ 노트 업데이트 실패: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 헬퍼 함수: 변경된 실제 정보만 생성 (업데이트 정보)
    func generateUpdatedInfo(for entry: [String: String]) -> String {
        let actualDepTime = entry["ActualDepTime"] ?? "N/A"
        let actualArrTime = entry["ActualArrTime"] ?? "N/A"
        let actualFlyingHours = entry["ActualFlyingHours"] ?? "N/A"
        let actualDutyHours = entry["ActualDutyHours"] ?? "N/A"
        
        return """
        Actual Departure: \(actualDepTime)
        Actual Arrival: \(actualArrTime)
        Actual Flying Hours: \(actualFlyingHours)
        Actual Duty Hours: \(actualDutyHours)
        """
    }
    
    // MARK: - 헬퍼 함수: 기본 노트 생성 (캘린더 이벤트 생성 시 사용)
    func generateBaseNote(for scheduleEntry: [String: String],
                          workType: String,
                          modifiedItem: String,
                          depStnTime: String,
                          depAp: String,
                          arrAp: String,
                          arrStnTime: String) -> String {
        let baseTitle = "\(modifiedItem) \(depStnTime) \(depAp) - \(arrAp) \(arrStnTime)"
        var noteText = ""
        if workType == "TVL" {
            noteText += "Deadhead\n"
        }
        noteText += baseTitle
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
        return noteText
    }
    
    // MARK: - CrewList 노트 빌더 (값이 있는 항목만 출력)
    private func buildCrewNote(from entry: [String: String]) -> String? {
        guard let json = entry["CrewList"],
              let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: String]],
              !arr.isEmpty else {
            return nil
        }
        
        let header = "Crew List (\(arr.count))"
        let lines: [String] = arr.map { row in
            var parts: [String] = []
            
            if let name = row["Name"], !name.isEmpty { parts.append(name) }
            if let duty = row["Duty"], !duty.isEmpty { parts.append("Duty=\(duty)") }
            if let act = row["ActingRank"], !act.isEmpty { parts.append("ActingRank=\(act)") }
            if let rank = row["PostingRank"], !rank.isEmpty { parts.append("Rank=\(rank)") }
            if let pic = row["PICCode"], !pic.isEmpty { parts.append("Code=\(pic)") }
            if let crewID = row["CrewID"], !crewID.isEmpty { parts.append("ID=\(crewID)") }
            if let contact = row["Contact"], !contact.isEmpty { parts.append("Contact=\(contact)") }
            if let sdc = row["SDC"], !sdc.isEmpty { parts.append("SDC=\(sdc)") }
            if let cmt = row["Comment"], !cmt.isEmpty { parts.append("Comment=\(cmt)") }
            
            return parts.isEmpty ? "• (정보 없음)" : "• " + parts.joined(separator: " • ")
        }
        
        return ([header] + lines).joined(separator: "\n\n")
    }
    
    // MARK: - ===== 업로드(파일) 임포트: PDF / XLSX =====
    
    // 공용 문서 선택기 (변경 없음)
    func pickDocument(allowedTypes: [UTType], onPick: @escaping (URL) -> Void) {
        onPickedFile = onPick
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker, animated: true)
    }
    
    // PDF → 텍스트 → 정규화 → 파싱 → 병합
    func importRosterFromPDF(url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            showAlert(title: "Import Fail", message: "Can't open PDF.")
            return
        }
        var raw = ""
        for i in 0..<pdf.pageCount {
            raw += (pdf.page(at: i)?.string ?? "")
            raw += "\n"
        }
        
        // 1) 전각 → 반각 보정
        var text = raw
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "＋", with: "+")
        
        // 2) 줄바꿈 뒤 (+n) 를 같은 줄로 합치기
        //    예) "GUM 01:30\n(+1)" -> "GUM 01:30 (+1)"
        if let re1 = try? NSRegularExpression(pattern: #"(\d{2}:\d{2})\s*\n\s*\(\s*([+\-]?\d+)\s*\)"#) {
            text = re1.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "$1 (+$2)")
        }
        if let re2 = try? NSRegularExpression(pattern: #"([A-Z]{3}\s+\d{2}:\d{2})\s*\n\s*\(\s*([+\-]?\d+)\s*\)"#) {
            text = re2.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "$1 (+$2)")
        }
        
        // 3) (중요) 전역 개행-공백 치환 제거 → 내용 유실 방지
        //    대신 단어중간 하이픈 개행만 보정
        if let hyphenJoin = try? NSRegularExpression(pattern: #"(\S)[\-–]\n(\S)"#) {
            text = hyphenJoin.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "$1$2")
        }
        
        let imported = parseRosterPDFText(text)
        mergeImportedSchedules(imported)
    }
    
    // MARK: - XLSX 임포트 (엄격 헤더: 2번째 줄 고정, 지정 컬럼만 사용, 디버그 강화)
    func importRosterFromXLSX(url: URL) {
        debugLog("📥 XLSX import start: \(url.lastPathComponent)")
        guard let file = XLSXFile(filepath: url.path) else {
            showAlert(title: "Import Fail", message: "Can't open XLSX.")
            debugLog("❌ XLSX open failed")
            return
        }
        
        // ---------- 로컬 유틸 ----------
        func norm(_ s: String) -> String {
            // 헤더 비교 용: 영숫자만 남기고 소문자
            let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let keep = CharacterSet.letters.union(.decimalDigits)
            return folded.unicodeScalars.filter { keep.contains($0) }.map(String.init).joined().lowercased()
        }
        func readText(_ cell: Cell, _ shared: SharedStrings?) -> String {
            if let ss = shared, let s = cell.stringValue(ss) { return s }
            if let v = cell.value { return v }
            if let f = cell.formula?.value { return f }
            return ""
        }
        // "ICN 10:30 (+1)" / "ICN 10:30" / "ICN" / "10:30 (+1)" / "10:30"
        func parseIataTime(_ raw: String) -> (ap: String, time: String, plus: Int) {
            let s = raw.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
            // 1) IATA + time (+off)
            if let r = try? NSRegularExpression(pattern: #"^\s*([A-Z]{3})\s+(\d{2}:\d{2})(?:\s*\(\s*([+\-]?\d+)\s*\))?\s*$"#),
               let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let ap = Range(m.range(at: 1), in: s).map { String(s[$0]) } ?? ""
                let t  = Range(m.range(at: 2), in: s).map { String(s[$0]) } ?? ""
                let p  = Range(m.range(at: 3), in: s).map { Int(String(s[$0])) ?? 0 } ?? 0
                return (ap, t, p)
            }
            // 2) time (+off)
            if let r = try? NSRegularExpression(pattern: #"^\s*(\d{2}:\d{2})(?:\s*\(\s*([+\-]?\d+)\s*\))?\s*$"#),
               let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let t  = Range(m.range(at: 1), in: s).map { String(s[$0]) } ?? ""
                let p  = Range(m.range(at: 2), in: s).map { Int(String(s[$0])) ?? 0 } ?? 0
                return ("", t, p)
            }
            // 3) IATA만
            if let r = try? NSRegularExpression(pattern: #"^\s*([A-Z]{3})\s*$"#),
               let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let ap = Range(m.range(at: 1), in: s).map { String(s[$0]) } ?? ""
                return (ap, "", 0)
            }
            return ("", "", 0)
        }
        func toOpt(_ plus: Int) -> String { plus == 0 ? "" : "(\(plus >= 0 ? "+" : "")\(plus))" }
        func shiftDate(_ ddMMMYYYY: String, plus: Int) -> String {
            guard plus != 0 else { return ddMMMYYYY }
            let df = DateFormatter(); df.locale = .init(identifier: "en_US_POSIX"); df.dateFormat = "dd-MMM-yyyy"
            guard let d = df.date(from: ddMMMYYYY),
                  let nd = Calendar.current.date(byAdding: .day, value: plus, to: d) else { return ddMMMYYYY }
            return df.string(from: nd)
        }
        func parseDateCell(_ raw: String) -> String {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return "" }
            let f1 = DateFormatter(); f1.locale = .init(identifier: "en_US_POSIX"); f1.dateFormat = "dd-MMM-yyyy"
            let f2 = DateFormatter(); f2.locale = .init(identifier: "en_US_POSIX"); f2.dateFormat = "yyyy-MM-dd"
            if let d = f1.date(from: t) { return f1.string(from: d) }
            if let d = f2.date(from: t) { return f1.string(from: d) }
            if let n = Double(t) {
                // 1900/1904 모두 시도
                if let d = excelSerialToDate(n, isDate1904: false) ?? excelSerialToDate(n, isDate1904: true) {
                    return f1.string(from: d)
                }
            }
            return ""
        }
        // MARK: - Excel serial number → Date 변환 (1900/1904 지원, UTC 고정)
        func excelSerialToDate(_ serial: Double, isDate1904: Bool) -> Date? {
            guard serial.isFinite else { return nil }
            let secondsPerDay = 86_400.0
            
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)! // 로컬 타임존 오프셋 영향 방지
            
            if isDate1904 {
                // Excel 1904 시스템: 0 = 1904-01-01
                var comps = DateComponents(); comps.year = 1904; comps.month = 1; comps.day = 1
                guard let base = cal.date(from: comps) else { return nil }
                return Date(timeInterval: serial * secondsPerDay, since: base)
            } else {
                // Excel 1900 시스템: 1 = 1900-01-01, (가짜) 1900-02-29 버그 보정
                var comps = DateComponents(); comps.year = 1899; comps.month = 12; comps.day = 31
                guard let base = cal.date(from: comps) else { return nil }
                var days = serial
                if serial >= 60 { days -= 1 } // 1900-02-29 건너뛰기
                return Date(timeInterval: days * secondsPerDay, since: base)
            }
        }
        
        func isFlightCode(_ s: String) -> Bool {
            s.range(of: #"^[A-Z]{2}\d{3,4}[A-Z]?$"#, options: .regularExpression) != nil
        }
        
        do {
            let sharedStrings = try file.parseSharedStrings()
            guard let wb = try file.parseWorkbooks().first else {
                showAlert(title: "Import Fail", message: "Workbook not found.")
                debugLog("❌ workbook not found")
                return
            }
            let sheets = try file.parseWorksheetPathsAndNames(workbook: wb)
            guard let first = sheets.first else {
                showAlert(title: "Import Fail", message: "No worksheet found.")
                debugLog("❌ no worksheet")
                return
            }
            let ws = try file.parseWorksheet(at: first.path)
            let rows = ws.data?.rows ?? []
            debugLog("📄 sheet: \(first.name ?? "(no name)") rows=\(rows.count)")
            
            guard !rows.isEmpty else {
                showAlert(title: "Import Fail", message: "Worksheet is empty.")
                debugLog("❌ worksheet empty")
                return
            }
            
            // ---- 헤더: 2번째 줄 고정 ----
            let headerRow: Row? = rows.first(where: { $0.reference == 2 }) ?? (rows.count > 1 ? rows[1] : nil)
            guard let hdr = headerRow else {
                showAlert(title: "Import Fail", message: "Header row (2) not found.")
                debugLog("❌ header row #2 not found")
                return
            }
            
            // (colLetter, text) 배열
            let headerPairs: [(String, String)] = hdr.cells.map { (String(describing: $0.reference.column), readText($0, sharedStrings)) }
            debugLog("🧭 Header@row2 raw: \(headerPairs.map { "\($0.0)=\($0.1)" }.joined(separator: " | "))")
            
            // 빈 헤더 셀 체크
            let emptyHeaders = headerPairs.filter { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { $0.0 }
            if !emptyHeaders.isEmpty {
                debugLog("⚠️ Empty header cells at columns: \(emptyHeaders.joined(separator: ", "))")
            }
            
            // 기대 헤더(정확한 항목)
            let expected: [(canon: String, label: String)] = [
                ("date","Date"),
                ("pairingactivity","Pairing/Activity"),
                ("report","Report"),
                ("item","Item"),
                ("optrank","Opt Rank"),
                ("wt","WT"),
                ("acyrep","ACY Rep"),
                ("dep","Dep"),
                ("arr","Arr"),
                ("acydeb","ACY Deb"),
                ("debrief","Debrief"),
                ("fh","FH"),
                ("dh","DH"),
                ("sdc","SDC"),
                ("actype","A/C Type"),
                ("hotel","Hotel"),
                ("assignmentcomments","Assignment Comments")
            ]
            
            // 헤더 매핑 (정확 일치만 허용)
            var colByCanon: [String:String] = [:]
            for (canon, label) in expected {
                if let hit = headerPairs.first(where: { norm($0.1) == norm(label) }) {
                    colByCanon[canon] = hit.0
                }
            }
            
            // 누락 헤더 디버그
            let missing = expected.filter { colByCanon[$0.canon] == nil }.map { $0.label }
            if !missing.isEmpty {
                debugLog("❌ Missing headers: \(missing.joined(separator: ", "))")
                showAlert(title: "XLSX Header mismatch",
                          message: "Not found in row 2: \(missing.joined(separator: ", "))")
                // 계속 진행은 가능하지만, 핵심 필드가 빠졌으면 무용지물이 될 수 있음
            } else {
                debugLog("✅ Header OK (row 2, strict match)")
            }
            
            // 값 얻기 유틸
            func v(_ canon: String, _ row: Row) -> String {
                guard let col = colByCanon[canon] else { return "" }
                if let cell = row.cells.first(where: { String(describing: $0.reference.column) == col }) {
                    return readText(cell, sharedStrings).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return ""
            }
            
            // ---- 본문(3번째 줄부터) 파싱 ----
            var newExtracted: [String: [[String:String]]] = [:]
            var seqCountersByDate: [String:Int] = [:]
            let airports = self.loadAirportList() ?? []
            var rowsParsed = 0
            
            for row in rows where row.reference > 2 {
                // 모든 필드 수집
                let dateRaw = v("date", row)
                let pairing = v("pairingactivity", row)
                let report  = v("report", row)
                let itemRaw = v("item", row)
                let optRank = v("optrank", row)
                let wtRaw   = v("wt", row).uppercased()
                let acyRep  = v("acyrep", row)
                let depStr  = v("dep", row)
                let arrStr  = v("arr", row)
                let acyDeb  = v("acydeb", row)
                let debrief = v("debrief", row)
                let fh      = v("fh", row)
                let dh      = v("dh", row)
                let sdc     = v("sdc", row)
                let acType  = v("actype", row)
                let hotel   = v("hotel", row)
                let comment = v("assignmentcomments", row)
                
                // 완전 빈 줄 스킵
                if [dateRaw,pairing,report,itemRaw,optRank,wtRaw,acyRep,depStr,arrStr,acyDeb,debrief,fh,dh,sdc,acType,hotel,comment]
                    .allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    continue
                }
                
                let baseDate = parseDateCell(dateRaw)
                if baseDate.isEmpty {
                    debugLog("⚠️ skip row@\(row.reference): invalid Date cell '\(dateRaw)'")
                    continue
                }
                
                // Dep/Arr
                let (depAp, depTime, depPlus) = parseIataTime(depStr)
                let (arrAp, arrTime, arrPlus) = parseIataTime(arrStr)
                // Duty report / debrief (둘 다 time(+off) 형태 or ACY Rep/Deb에서 뽑기)
                let (_, repTime, _) = !acyRep.isEmpty ? parseIataTime(acyRep) : parseIataTime(report)
                let (_, debTime1, debPlus1) = parseIataTime(debrief)
                let (_, debTime2, debPlus2) = parseIataTime(acyDeb)
                let (debTime, debPlus) = debTime1.isEmpty ? (debTime2, debPlus2) : (debTime1, debPlus1)
                
                var item = itemRaw.isEmpty ? pairing : itemRaw
                var workType = wtRaw
                var isDH = false
                
                // DH #### → KE#### + WT=TVL
                if item.range(of: #"^DH\s*\d{3,4}[A-Z]?$"#, options: .regularExpression) != nil {
                    if let r = item.range(of: #"^DH\s*(\d{3,4}[A-Z]?)$"#, options: .regularExpression) {
                        let tail = String(item[r]).replacingOccurrences(of: "DH", with: "").trimmingCharacters(in: .whitespaces)
                        item = "KE\(tail)"; workType = "TVL"; isDH = true
                    }
                }
                if workType.isEmpty, isFlightCode(item) { workType = "FLY" }
                
                // 날짜 확정
                let depDate = depTime.isEmpty ? baseDate : shiftDate(baseDate, plus: depPlus)
                let arrDate = arrTime.isEmpty ? baseDate : shiftDate(baseDate, plus: arrPlus)
                let debDate = debTime.isEmpty ? baseDate : shiftDate(baseDate, plus: debPlus)
                
                // UTC 변환
                let depUTC = (!depTime.isEmpty && !depAp.isEmpty) ? convertLocalTimeToUTCTime(dateString: depDate, timeString: depTime, airportCode: depAp, airports: airports) : "N/A"
                let arrUTC = (!arrTime.isEmpty && !arrAp.isEmpty) ? convertLocalTimeToUTCTime(dateString: arrDate, timeString: arrTime, airportCode: arrAp, airports: airports) : "N/A"
                
                // 저장 키: 비행은 DepDate 기준, 지상은 baseDate 기준으로 정렬감을 맞춥니다.
                let bucketKey = (workType == "FLY" || workType == "TVL") ? depDate : baseDate
                let seq = (seqCountersByDate[bucketKey] ?? 0) + 1
                seqCountersByDate[bucketKey] = seq
                
                let entry: [String:String] = [
                    "Seq": "\(seq)",
                    "Activity": item.isEmpty ? (pairing.isEmpty ? "DUTY" : pairing) : item,
                    "Item": item.isEmpty ? (pairing.isEmpty ? "DUTY" : pairing) : item,
                    "WorkType": workType,
                    "DutyReport": repTime,
                    "DepAp": depAp,
                    "DepStnTime": depTime.isEmpty ? (workType == "FLY" || workType == "TVL" ? "" : "N/A") : depTime,
                    "DepStnTimeOpt": toOpt(depPlus),
                    "DepDate": depDate,
                    "ArrAp": arrAp.isEmpty ? depAp : arrAp,
                    "ArrStnTime": arrTime.isEmpty ? (workType == "FLY" || workType == "TVL" ? "" : "N/A") : arrTime,
                    "ArrStnTimeOpt": toOpt(arrPlus),
                    "ArrDate": arrDate,
                    "DutyDebrief": debTime,
                    "DutyDebriefTime": debTime,
                    "DutyDebriefDate": debDate,
                    "FlyingHours": fh,
                    "DutyHours": dh,
                    //"SDC": sdc,
                    "Hotel": hotel,
                    "DepStnTimeUTC": depUTC,
                    "ArrStnTimeUTC": arrUTC,
                    "Date": baseDate,
                    "AC": acType,
                    "ActingRank": optRank,
                    "Comment": comment
                ]
                
                // TVL 제목 보정용 아이템(캘린더용에 영향 없음)
                if isDH && (entry["Item"] ?? "").hasPrefix("KE") {
                    // 표시만 KE로, 노트 생성 시 Deadhead로 표현됨
                }
                
                newExtracted[bucketKey, default: []].append(entry)
                rowsParsed += 1
            }
            
            guard rowsParsed > 0, !newExtracted.isEmpty else {
                showAlert(title: "No sched rows in XLSX",
                          message: "Row 3+ contained no usable data. Check the header row and body formatting.")
                debugLog("⚠️ parsed rows=0")
                return
            }
            
            // === 기존 코드 제거 ===
            // for (k, v) in newExtracted { schedules[k] = v }
            // saveSchedules()
            // printSchedulesToConsole()
            // showAlert(...)
            
            // === 병합 저장(FLY/TVL: 특정 필드만 업데이트, CrewList 보존) ===
            func makeKey(_ e: [String:String]) -> String {
                let wt = (e["WorkType"] ?? "").uppercased()
                if wt == "FLY" || wt == "TVL" {
                    // 비행 키: DepDate + Item + DepAp + DepStnTime
                    return [
                        e["DepDate"] ?? "",
                        e["Item"] ?? "",
                        e["DepAp"] ?? "",
                        e["DepStnTime"] ?? ""
                    ].joined(separator: "|")
                } else {
                    // 지상 키: Date(없으면 DepDate) + Activity + DutyReport + DutyDebriefTime
                    return [
                        e["Date"] ?? (e["DepDate"] ?? ""),
                        e["Activity"] ?? "",
                        e["DutyReport"] ?? "",
                        e["DutyDebriefTime"] ?? ""
                    ].joined(separator: "|")
                }
            }
            
            for (bucketKey, entries) in newExtracted {
                var merged = schedules[bucketKey] ?? []
                var indexByKey: [String:Int] = [:]
                for (i, e) in merged.enumerated() { indexByKey[makeKey(e)] = i }
                
                for e in entries {
                    let wt = (e["WorkType"] ?? "").uppercased()
                    let k = makeKey(e)
                    
                    if let idx = indexByKey[k] {
                        var old = merged[idx]
                        
                        if wt == "FLY" || wt == "TVL" {
                            // ✈️ 비행 듀티: 특정 필드만 덮어쓰기, CrewList는 그대로 둠
                            func assign(_ key: String) {
                                if let v = e[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                                    old[key] = v
                                }
                            }
                            assign("DutyReport")        // Report
                            assign("DutyDebrief")       // Debrief(문자)
                            assign("DutyDebriefTime")   // Debrief(시간)
                            assign("FlyingHours")       // FH
                            assign("DutyHours")         // DH
                            assign("Hotel")             // Hotel
                            // CrewList는 건드리지 않음
                            merged[idx] = old
                            
                        } else {
                            // 🧱 지상 듀티: 값 있는 항목만 덮어쓰기, CrewList는 비어있을 때만 채움
                            for (kk, vv) in e {
                                if kk == "CrewList" { continue } // 기존 CrewList 보호
                                let v = vv.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !v.isEmpty { old[kk] = v }
                            }
                            if (old["CrewList"] ?? "").isEmpty, let c = e["CrewList"], !c.isEmpty {
                                old["CrewList"] = c
                            }
                            merged[idx] = old
                        }
                        
                    } else {
                        // 기존에 없는 스케줄은 새로 추가 (FLY/TVL 포함)
                        merged.append(e)
                        indexByKey[makeKey(e)] = merged.count - 1
                    }
                }
                
                // Seq 재부여
                for i in merged.indices { merged[i]["Seq"] = String(i+1) }
                schedules[bucketKey] = merged
            }
            
            saveSchedules()
            printSchedulesToConsole()
            showAlert(
                title: "Import Complete",
                message: "XLSX merged."
            )
            
            
            // ▶ 기존 덮어쓰기 블록 제거 후 교체:
            //mergeImportedSchedules(newExtracted)
           // return  // (중복 알림 방지용. merge 함수에서 alert 띄웁니다)

            
        } catch {
            debugLog("❌ XLSX parse error: \(error)")
            showAlert(title: "Import Fail", message: error.localizedDescription)
        }
    }
    
    
    
    // ===== PDF 텍스트 라인 파서 (보강본: 키워드 의존 X, 첫 토큰 추출 지원) =====
    private func parseRosterPDFText(_ text: String) -> [String: [[String:String]]] {
        var bucket: [String: [[String:String]]] = [:]
        
        // --- 정규식들 ---
        let reDate = try! NSRegularExpression(pattern: #"(?m)^(\d{2}-[A-Za-z]{3}-\d{4})\b"#)
        let reFlightCode = try! NSRegularExpression(pattern: #"\b([A-Z]{2}\d{3,4}[A-Z]?)\b"#)
        let reDHInline  = try! NSRegularExpression(pattern: #"\bDH\s*\d{3,4}[A-Z]?\b"#)
        let reIATATime  = try! NSRegularExpression(pattern: #"\b([A-Z]{3})\s+(\d{2}:\d{2})(?:\s*[\(（]\s*([+\-]?\d+)\s*[\)）])?"#)
        let reTimeWithOffset = try! NSRegularExpression(pattern: #"(\d{2}:\d{2})(?:\s*[\(（]\s*([+\-]?\d+)\s*[\)）])?"#)
        let reLabeledTail = try! NSRegularExpression(
            pattern: #"\b(ACY\s*Deb|Debrief|FH|DH)\b[:\-]?\s*(\d{2}:\d{2})(?:\s*[\(（]\s*([+\-]?\d+)\s*[\)）])?"#,
            options: [.caseInsensitive]
        )
        let reACYRep = try! NSRegularExpression(pattern: #"(?i)\bACY\s*Rep\b.*?(\d{2}:\d{2})(?:\s*[\(（]\s*([+\-]?\d+)\s*[\)）])?"#)
        let reACYDeb = try! NSRegularExpression(pattern: #"(?i)\bACY\s*Deb\b.*?(\d{2}:\d{2})(?:\s*[\(（]\s*([+\-]?\d+)\s*[\)）])?"#)
        // 🔹 지상 듀티 이름을 키워드에 의존하지 않기 위해 "첫 토큰"을 잡는 정규식
        let reFirstToken = try! NSRegularExpression(pattern: #"^\s*([A-Z][A-Z0-9_]{1,})\b"#)
        
        // --- 헬퍼 ---
        func matches(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
            re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        }
        func cap(_ s: String, _ m: NSTextCheckingResult, _ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
        func shiftDate(_ dateStr: String, plus: Int) -> String {
            guard plus != 0 else { return dateStr }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "dd-MMM-yyyy"
            guard let d = df.date(from: dateStr),
                  let nd = Calendar.current.date(byAdding: .day, value: plus, to: d) else { return dateStr }
            return df.string(from: nd)
        }
        
        // 아이템 시작 트리거(편명 / DH #### / 지상: 첫 토큰으로 시작하는 라인)
        let reItemStart = try! NSRegularExpression(
            pattern: #"\b(?:[A-Z]{2}\d{3,4}[A-Z]?|DH\s*\d{3,4}[A-Z]?|[A-Z][A-Z0-9_]{1,})\b"#
        )
        
        // 날짜 매치들
        let dateMatches = matches(reDate, text)
        guard !dateMatches.isEmpty else { return [:] }
        
        for (idx, dm) in dateMatches.enumerated() {
            guard let dateRange = Range(dm.range(at: 1), in: text) else { continue }
            let dateStr = String(text[dateRange])
            let start = dateRange.upperBound
            let end: String.Index = {
                if idx+1 < dateMatches.count, let r = Range(dateMatches[idx+1].range(at: 1), in: text) {
                    return r.lowerBound
                } else {
                    return text.endIndex
                }
            }()
            
            let block = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if block.isEmpty { continue }
            
            // 아이템 시작 위치들
            let starts = matches(reItemStart, block)
            if starts.isEmpty { continue }
            
            var segments: [String] = []
            for (i, m) in starts.enumerated() {
                let segStart = Range(m.range, in: block)!.lowerBound
                let segEnd: String.Index = {
                    if i+1 < starts.count, let r = Range(starts[i+1].range, in: block) {
                        return r.lowerBound
                    } else {
                        return block.endIndex
                    }
                }()
                let seg = block[segStart..<segEnd].trimmingCharacters(in: .whitespacesAndNewlines)
                if !seg.isEmpty { segments.append(String(seg)) }
            }
            
            for raw in segments {
                let hasFlightCode = !matches(reFlightCode, raw).isEmpty
                let hasDHOnly     = !matches(reDHInline, raw).isEmpty
                let isFlightLine  = hasFlightCode || hasDHOnly
                
                if isFlightLine {
                    // Report(첫 시간)
                    let timeMatches = matches(reTimeWithOffset, raw)
                    let reportTime = timeMatches.first.map { cap(raw, $0, 1) } ?? ""
                    
                    // Dep/Arr
                    let apMatches = matches(reIATATime, raw)
                    guard apMatches.count >= 2 else { continue }
                    
                    let depAp   = cap(raw, apMatches[0], 1)
                    let depTime = cap(raw, apMatches[0], 2)
                    let depPlus = Int(cap(raw, apMatches[0], 3)) ?? 0
                    
                    let arrAp   = cap(raw, apMatches[1], 1)
                    let arrTime = cap(raw, apMatches[1], 2)
                    let arrPlus = Int(cap(raw, apMatches[1], 3)) ?? 0
                    
                    let depDate = shiftDate(dateStr, plus: depPlus)
                    let arrDate = shiftDate(dateStr, plus: arrPlus)
                    
                    // Item / WorkType
                    var item = ""
                    if let lastCode = matches(reFlightCode, raw).last {
                        item = cap(raw, lastCode, 1)
                    }
                    var workType = ""
                    if hasDHOnly && item.isEmpty {
                        if let m = matches(reDHInline, raw).last {
                            let whole = cap(raw, m, 0)
                            let tail = whole.replacingOccurrences(of: "DH", with: "").trimmingCharacters(in: .whitespaces)
                            item = "KE\(tail)"; workType = "TVL"
                        }
                    } else if hasFlightCode {
                        workType = "FLY"
                    }
                    
                    // 꼬리 (Deb/FH/DH)
                    var tailStr = ""
                    if let arrR = Range(apMatches[1].range, in: raw) {
                        tailStr = String(raw[arrR.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    let labeled = matches(reLabeledTail, tailStr)
                    var acyDebTime = "", acyPlus = 0, debriefTime = "", debPlus = 0, fh = "", dh = ""
                    if !labeled.isEmpty {
                        for m in labeled {
                            let label = cap(tailStr, m, 1).replacingOccurrences(of: " ", with: "").uppercased()
                            let t = cap(tailStr, m, 2); let p = Int(cap(tailStr, m, 3)) ?? 0
                            switch label {
                            case "ACYDEB": acyDebTime=t; acyPlus=p
                            case "DEBRIEF": debriefTime=t; debPlus=p
                            case "FH": fh=t
                            case "DH": dh=t
                            default: break
                            }
                        }
                    } else {
                        let tailTimes = matches(reTimeWithOffset, tailStr)
                        if tailTimes.count >= 1 { acyDebTime = cap(tailStr, tailTimes[0], 1); acyPlus = Int(cap(tailStr, tailTimes[0], 2)) ?? 0 }
                        if tailTimes.count >= 2 { debriefTime = cap(tailStr, tailTimes[1], 1); debPlus = Int(cap(tailStr, tailTimes[1], 2)) ?? 0 }
                        if tailTimes.count >= 3 { fh = cap(tailStr, tailTimes[2], 1) }
                        if tailTimes.count >= 4 { dh = cap(tailStr, tailTimes[3], 1) }
                    }
                    let dutyDebTime = debriefTime.isEmpty ? acyDebTime : debriefTime
                    let dutyDebPlus = debriefTime.isEmpty ? acyPlus : debPlus
                    let dutyDebDate = shiftDate(dateStr, plus: dutyDebPlus)
                    
                    let activity = item.isEmpty ? "FLY" : item
                    
                    var entry: [String:String] = [
                        "Seq":"0","Activity":activity,"Item": item.isEmpty ? activity : item,"WorkType":workType,
                        "DutyReport":reportTime,"DepAp":depAp,"DepStnTime":depTime,"DepStnTimeOpt": depPlus==0 ? "" : "(+\(depPlus))","DepDate":depDate,
                        "ArrAp":arrAp,"ArrStnTime":arrTime,"ArrStnTimeOpt": arrPlus==0 ? "" : "(+\(arrPlus))","ArrDate":arrDate,
                        "DutyDebrief":dutyDebTime,"DutyDebriefTime":dutyDebTime,"DutyDebriefDate":dutyDebDate,
                        "FlyingHours":fh,"DutyHours":dh,"SDC":"","Hotel":"","DepStnTimeUTC":"","ArrStnTimeUTC":"","Date":dateStr
                    ]
                    if let airports = loadAirportList() {
                        if !depTime.isEmpty { entry["DepStnTimeUTC"] = convertLocalTimeToUTCTime(dateString: depDate, timeString: depTime, airportCode: depAp, airports: airports) }
                        if !arrTime.isEmpty { entry["ArrStnTimeUTC"] = convertLocalTimeToUTCTime(dateString: arrDate, timeString: arrTime, airportCode: arrAp, airports: airports) }
                    }
                    bucket[dateStr, default: []].append(entry)
                    continue
                }
                
                // ── 지상 듀티 (WT 공란) ──────────────────────────
                // 이름: 첫 토큰 사용 (키워드 의존 X)
                var activity = "DUTY"
                if let m = matches(reFirstToken, raw).first { activity = cap(raw, m, 1) }
                
                // Rep / Deb 시간
                var repTime = ""
                var repPlus = 0
                if let m = matches(reACYRep, raw).first {
                    repTime = cap(raw, m, 1)
                    repPlus = Int(cap(raw, m, 2)) ?? 0
                }
                var debTime = ""
                var debPlus = 0
                if let m = matches(reACYDeb, raw).first {
                    debTime = cap(raw, m, 1)
                    debPlus = Int(cap(raw, m, 2)) ?? 0
                }
                // 폴백: 라인 내 시간들에서 Rep → Deb 순으로 선택
                if repTime.isEmpty, let f = matches(reTimeWithOffset, raw).first {
                    repTime = cap(raw, f, 1); repPlus = Int(cap(raw, f, 2)) ?? 0
                }
                if debTime.isEmpty {
                    let all = matches(reTimeWithOffset, raw)
                    if let cand = all.first(where: { cap(raw, $0, 1) != repTime }) {
                        debTime = cap(raw, cand, 1); debPlus = Int(cap(raw, cand, 2)) ?? 0
                    } else {
                        debTime = repTime; debPlus = repPlus
                    }
                }
                
                // 공항: 첫 IATA → dep/arr 동일(없으면 ICN)
                let apMatches2 = matches(reIATATime, raw)
                let depAp = apMatches2.first.map { cap(raw, $0, 1) } ?? "ICN"
                let arrAp = apMatches2.dropFirst().first.map { cap(raw, $0, 1) } ?? depAp
                
                let entry: [String:String] = [
                    "Seq":"0","Activity":activity,"Item":activity,"WorkType":"",
                    "DutyReport":repTime,"DepAp":depAp,"DepStnTime":"N/A","DepStnTimeOpt": repPlus==0 ? "" : "(+\(repPlus))",
                    "DepDate": shiftDate(dateStr, plus: repPlus),
                    "ArrAp":arrAp,"ArrStnTime":"N/A","ArrStnTimeOpt":"",
                    "ArrDate": dateStr,
                    "DutyDebrief":debTime,"DutyDebriefTime":debTime,"DutyDebriefDate": shiftDate(dateStr, plus: debPlus),
                    "FlyingHours":"","DutyHours":"","SDC":"","Hotel":"","DepStnTimeUTC":"N/A","ArrStnTimeUTC":"N/A","Date":dateStr
                ]
                bucket[dateStr, default: []].append(entry)
            }
        }
        
        // Seq 부여
        for (k, var v) in bucket {
            for i in v.indices { v[i]["Seq"] = String(i+1) }
            bucket[k] = v
        }
        return bucket
    }
    
    // 병합 로직 (XLSX/PDF 공용):
    // - FLY/TVL: 기존 엔트리는 유지하고 Report/Debrief/FH/DH/Hotel만 업데이트 (CrewList는 건드리지 않음)
    // - Ground: SDC는 절대 반영하지 않음(무시). 값 있는 필드만 업데이트, CrewList도 덮어쓰지 않음
    // - 기존에 없는 스케줄은 새로 추가(FLY/TVL 포함). 단, Ground 신규 추가시 SDC는 빈 값으로 강제
    private func mergeImportedSchedules(_ incoming: [String: [[String:String]]]) {
        func key(_ e: [String:String]) -> String {
            let wt = (e["WorkType"] ?? "").uppercased()
            if wt == "FLY" || wt == "TVL" {
                // 비행 키: DepDate + Item + DepAp + DepStnTime
                let d = e["DepDate"] ?? ""
                let i = e["Item"] ?? ""
                let a = e["DepAp"] ?? ""
                let t = e["DepStnTime"] ?? ""
                return [d,i,a,t].joined(separator: "|")
            } else {
                // 지상 키: Date(없으면 DepDate) + Activity + DutyReport + DutyDebriefTime
                let d = e["Date"] ?? (e["DepDate"] ?? "")
                let act = e["Activity"] ?? ""
                let rep = e["DutyReport"] ?? ""
                let deb = e["DutyDebriefTime"] ?? ""
                return [d,act,rep,deb].joined(separator: "|")
            }
        }
        
        var depMonthCount: [String:Int] = [:]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "dd-MMM-yyyy"
        
        for (dateKey, newEntries) in incoming {
            var merged = schedules[dateKey] ?? []
            var indexByKey: [String:Int] = [:]
            for (idx, e) in merged.enumerated() { indexByKey[key(e)] = idx }
            
            for var e in newEntries {
                // 월 카운트 (그래프/합계 유지)
                if let d = df.date(from: e["DepDate"] ?? dateKey) {
                    depMonthCount[formattedMonth(for: d), default: 0] += 1
                }
                
                let wt = (e["WorkType"] ?? "").uppercased()
                let k = key(e)
                
                if let idx = indexByKey[k] {
                    // ── 기존 엔트리 병합 ─────────────────────────────
                    var old = merged[idx]
                    if wt == "FLY" || wt == "TVL" {
                        // ✈️ 비행: 지정 필드만 업데이트 (CrewList는 절대 건드리지 않음)
                        let allow = ["DutyReport","DutyDebrief","DutyDebriefTime","FlyingHours","DutyHours","Hotel"]
                        for f in allow {
                            if let v = e[f]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                                old[f] = v
                            }
                        }
                    } else {
                        // 🧱 그라운드: SDC는 무시, CrewList도 덮어쓰지 않음. 값 있는 필드만 업데이트
                        for (kk, vv) in e {
                            if kk == "SDC" || kk == "CrewList" { continue }  // SDC 무시 + CrewList 보호
                            let v = vv.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !v.isEmpty { old[kk] = v }
                        }
                    }
                    merged[idx] = old
                } else {
                    // ── 신규 엔트리 추가(FLY/TVL 포함) ────────────────
                    if wt != "FLY" && wt != "TVL" {
                        // Ground는 SDC 가져오지 않음 → 빈 값으로 강제
                        e["SDC"] = ""
                    }
                    merged.append(e)
                    indexByKey[k] = merged.count - 1
                }
            }
            
            // Seq 재부여
            for i in merged.indices { merged[i]["Seq"] = String(i+1) }
            schedules[dateKey] = merged
        }
        
        // 월별 합계 키 유지(기존 로직 유지)
        if let (monthKey, _) = depMonthCount.max(by: { $0.value < $1.value }) {
            var monthlyStd = UserDefaults.standard.dictionary(forKey: totalHoursByMonthUserDefaultsKey) as? [String:String] ?? [:]
            if monthlyStd[monthKey] == nil { monthlyStd[monthKey] = totalHours }
            UserDefaults.standard.set(monthlyStd, forKey: totalHoursByMonthUserDefaultsKey)
        }
        
        saveSchedules()
        printSchedulesToConsole()
        showAlert(
            title: "Import Complete",
            message: "Merged (XLSX/PDF)."
        )
    }
}

// MARK: - UIDocumentPickerDelegate
extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        onPickedFile?(url)
        onPickedFile = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onPickedFile = nil
    }
}
