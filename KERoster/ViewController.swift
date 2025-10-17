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

    // MARK: - 고유 ID 생성 함수 (날짜와 Activity 값을 조합
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
        // 모든 프레임(iframe 포함)에 Ocean 배경을 칠하는 사용자 스크립트 설치
        installOceanFooterUserScript()
        // iCloud → 로컬(App Group) 폴백 순서로 로드
        NSUbiquitousKeyValueStore.default.synchronize()
        loadFromICloudKVS()
        if self.schedules.isEmpty { loadSchedules() }
        startObservingiCloudKVSChanges()

        // Info.plist에서 버전과 빌드 정보 가져오기
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
            
            // ⬇︎ 추가: 탭 가능 + 제스처
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

        // 오른쪽 네비게이션 바 버튼 (스토리보드 연결이 안되어 있으면 생성)
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
        // ✅ 크루리스트 가져오기 메뉴 추가
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
        let menu = UIMenu(title: "Select a task", children: [importAction, importCrewAction, exportAction])
        navigationItem.rightBarButtonItem?.menu = menu
    }

    deinit {
        // 옵저버 정리
        NotificationCenter.default.removeObserver(self, name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("KVSUpdated"), object: nil)
    }

    // MARK: - iCloud KVS 키
    private enum KVSKeys {
        static let schedulesJSON = "schedules_json"
        static let ownerInfo = "ownerInfo"
        static let totalHoursByMonthJSON = "totalHoursByMonth_json"
    }

    // MARK: - iCloud KVS 저장/로드/옵저버
    func saveToICloudKVS() {
        let kvs = NSUbiquitousKeyValueStore.default
        if let data = try? JSONEncoder().encode(self.schedules),
           let json = String(data: data, encoding: .utf8) {
            kvs.set(json, forKey: KVSKeys.schedulesJSON)
        }
        kvs.set(self.ownerInfo, forKey: KVSKeys.ownerInfo)

        let monthlyStd = UserDefaults.standard.dictionary(forKey: self.totalHoursByMonthUserDefaultsKey) as? [String: String] ?? [:]
        if let data = try? JSONEncoder().encode(monthlyStd),
           let json = String(data: data, encoding: .utf8) {
            kvs.set(json, forKey: KVSKeys.totalHoursByMonthJSON)
        }
        kvs.synchronize()

        // App Group에도 미러링 (위젯 사용)
        if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
            shared.set(self.ownerInfo, forKey: self.ownerUserDefaultsKey)
            shared.set(monthlyStd, forKey: self.totalHoursByMonthUserDefaultsKey)
            shared.synchronize()
        }

        // 위젯 최신화
        WidgetCenter.shared.reloadAllTimelines()
        debugLog("iCloud KVS 저장 완료 & App Group 미러링 & 위젯 갱신")
    }

    func loadFromICloudKVS() {
        let kvs = NSUbiquitousKeyValueStore.default

        if let json = kvs.string(forKey: KVSKeys.schedulesJSON),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
            self.schedules = decoded
            debugLog("iCloud KVS에서 schedules 로드")
        }

        if let json = kvs.string(forKey: KVSKeys.totalHoursByMonthJSON),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            // 표준 UD + App Group 모두 반영
            UserDefaults.standard.set(decoded, forKey: self.totalHoursByMonthUserDefaultsKey)
            if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
                shared.set(decoded, forKey: self.totalHoursByMonthUserDefaultsKey)
                shared.synchronize()
            }
            self.totalHours = decoded.values.first ?? self.totalHours
        }

        if let owner = kvs.string(forKey: KVSKeys.ownerInfo) {
            self.ownerInfo = owner
            if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
                shared.set(owner, forKey: self.ownerUserDefaultsKey)
                shared.synchronize()
            }
        }
    }

    func startObservingiCloudKVSChanges() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.debugLog("iCloud KVS 외부 변경 감지 → 로드 & 로컬(App Group) 캐시 저장")
            self.loadFromICloudKVS()
            self.saveSchedules() // App Group에도 최신화 + KVS 동기 저장
            self.printSchedulesToConsole()
            WidgetCenter.shared.reloadAllTimelines()
        }
        // AppDelegate 브로드캐스트도 함께 수신(선택)
        NotificationCenter.default.addObserver(forName: Notification.Name("KVSUpdated"),
                                               object: nil, queue: .main) { [weak self] _ in
            self?.loadFromICloudKVS()
            self?.saveSchedules()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 첫 진입 시 페이지 로드
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
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

        // 앱 내에서 열고 싶다면 위 3줄 대신 아래 두 줄:
        // let safari = SFSafariViewController(url: url)
        // present(safari, animated: true)
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
    // 페이지 로드 완료 후 하단 메뉴(웹 콘텐츠의 푸터/바) 배경을 Ocean 색으로 강제 적용
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectOceanFooterCSS()
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
    
    // MARK: - 하단 메뉴(웹 내부) 배경을 Ocean 색으로 강제 적용
    private func injectOceanFooterCSS() {
        let hex = webSafeOceanHex()
        let js = """
        (function(){
          const OCEAN = '\(hex)';
          function paint(el){
            try{
                  el.style.setProperty('background-color', OCEAN, 'important');
                  el.style.setProperty('background-image', 'none', 'important');
                  el.style.setProperty('backdrop-filter', 'none', 'important');
                  el.style.setProperty('-webkit-backdrop-filter', 'none', 'important');
                  el.style.setProperty('opacity', '1', 'important');
            }catch(e){}
          }
          const selectors = [
            'footer','#footer','.footer',
            '.bottom-bar','.bottomBar','.fixed-bottom','.navbar-fixed-bottom',
                '[class*="bottom-nav"]','[class*="BottomNav"]','[id*="bottom"]',
                'ion-tab-bar','mat-bottom-sheet-container','mat-bottom-navigation'
          ];
          function run(){
            document.querySelectorAll(selectors.join(',')).forEach(paint);
            // 화면 하단에 고정된 바(푸터)도 탐지해서 칠함
            Array.from(document.body.querySelectorAll('*')).forEach(el=>{
              const st = getComputedStyle(el);
              const h = parseInt(st.height||'0',10);
                  if (st.position === 'fixed' && (st.bottom === '0px' || st.top === 'auto') && h >= 40 && h <= 160) {
                paint(el);
              }
            });
          }
          run();
          // SPA/동적 변경 대비
          setTimeout(run, 500);
          if (!window.__keroster_ocean_obs){
                window.__keroster_ocean_obs = new MutationObserver(()=>setTimeout(run,0));
                window.__keroster_ocean_obs.observe(document.documentElement,{subtree:true,childList:true,attributes:true});
                document.addEventListener('visibilitychange', run, true);
          }
        })();
        """
        webView.evaluateJavaScript(js) { _, err in
            if let err = err { self.debugLog("Ocean CSS 주입 실패: \(err.localizedDescription)") }
            else { self.debugLog("Ocean CSS 주입 완료") }
        }
    }

    // 모든 프레임(iframe 포함)에 자동 주입되는 WKUserScript 버전
    private func installOceanFooterUserScript() {
        let hex = webSafeOceanHex()
        let src = """
        (function(){
          const OCEAN = '\(hex)';
          function paint(el){
            try{
              el.style.setProperty('background-color', OCEAN, 'important');
              el.style.setProperty('background-image', 'none', 'important');
              el.style.setProperty('backdrop-filter', 'none', 'important');
              el.style.setProperty('-webkit-backdrop-filter', 'none', 'important');
              el.style.setProperty('opacity', '1', 'important');
            }catch(e){}
          }
          const selectors = [
            'footer','#footer','.footer',
            '.bottom-bar','.bottomBar','.fixed-bottom','.navbar-fixed-bottom',
            '[class*="bottom-nav"]','[class*="BottomNav"]','[id*="bottom"]',
            'ion-tab-bar','mat-bottom-sheet-container','mat-bottom-navigation'
          ];
          function run(){
            try{
              document.querySelectorAll(selectors.join(',')).forEach(paint);
              Array.from(document.body.querySelectorAll('*')).forEach(el=>{
                const st = getComputedStyle(el);
                const h = parseInt(st.height||'0',10);
                if (st.position === 'fixed' && (st.bottom === '0px' || st.top === 'auto') && h >= 40 && h <= 160){
                  paint(el);
                }
              });
            }catch(e){}
          }
          run();
          setTimeout(run, 500);
          if (!window.__keroster_ocean_obs){
            window.__keroster_ocean_obs = new MutationObserver(()=>setTimeout(run,0));
            window.__keroster_ocean_obs.observe(document.documentElement,{subtree:true,childList:true,attributes:true});
            document.addEventListener('visibilitychange', run, true);
          }
        })();
        """
        let us = WKUserScript(source: src, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(us)
        debugLog("WKUserScript(Ocean) installed")
    }
    private func webSafeOceanHex() -> String {
        // Asset의 "Ocean" 색이 있으면 우선 사용, 없으면 기본 파랑 계열로 폴백
        let c = UIColor(named: "Ocean") ?? UIColor(red: 10/255, green: 108/255, blue: 197/255, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func hx(_ v: CGFloat) -> String { String(format: "%02X", Int(round(v*255))) }
        return "#\(hx(r))\(hx(g))\(hx(b))"
    }
    // MARK: - UserDefaults 관련 (스케줄 저장/불러오기)
    func saveSchedules() {
        if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
            do {
                let data = try JSONEncoder().encode(schedules)
                sharedDefaults.set(data, forKey: schedulesUserDefaultsKey)
                sharedDefaults.synchronize()
                print("스케줄 저장 성공")
                // iCloud에도 동시 반영
                self.saveToICloudKVS()
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
            //  var currentFlightKey: String? = nil
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


                        // 예상 매핑(양 끝 공백셀 포함 15열)
                        // 0:'', 1:Flight/Activity, 2:From, 3:STD, 4:To, 5:STA, 6:A/C, 7:Acting rank,
                        // 8:Duty, 9:PIC code, 10:Crew ID, 11:Name, 12:Comment, 13:Special Duty Code, 14:''
                        let item = cell(1)
                        let depAp = cell(2)
                        let stdRaw = cell(3)
                        let arrAp = cell(4)
                        let staRaw = cell(5)
                        let ac = cell(6)
                        let actingRank = cell(7)
                        let duty = cell(8)
                        let picCode = cell(9)
                        let crewID = cell(10)
                        let crewName = cell(11)
                        let comment = cell(12)
                        let sdcPerCrew = cell(13)

                        // 크루 칼럼 중 하나라도 값이 있으면 "크루 내용 있음"
                        let hasCrew = [actingRank, duty, picCode, crewID, crewName, comment, sdcPerCrew]
                            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                        // 새 비행편 시작 행인지 판별
                        let isNewFlightRow: Bool = {
                            // 아이템/공항/시간 5요소 중 3개 이상 있으면 새 편으로 간주
                            let bits = [item, depAp, stdRaw, arrAp, staRaw].map { !$0.isEmpty }
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

                            // 편 키/포지션
                            let fKey = flightKey(item: item, depDate: depDate, depAp: depAp, depTime: depTime)

                            // 신규/기존 분기
                            if let existingPos = indexMap[fKey] {                                // 이미 만든 편이 있으면 대표 필드만 보강하고 이어서 크루 병합
                                var arrForDate = newExtracted[existingPos.dateKey] ?? []
                                var entry = arrForDate[existingPos.idx]
                                if entry["AC"]?.isEmpty ?? true, !ac.isEmpty { entry["AC"] = ac }
                                if entry["ActingRank"]?.isEmpty ?? true, !actingRank.isEmpty { entry["ActingRank"] = actingRank }
                                if entry["WorkType"]?.isEmpty ?? true, !duty.isEmpty { entry["WorkType"] = duty }
                                if hasCrew {
                                    let crewRow: [String:String] = [
                                        "ActingRank": actingRank,
                                        "Duty": duty,
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

                              //currentFlightKey = fKey
                                currentPos = existingPos
                            } else {
                                let seq = (seqCountersByDate[depDate] ?? 0) + 1
                                seqCountersByDate[depDate] = seq

                                var entry: [String:String] = [
                                    "Seq": "\(seq)",
                                    "Activity": item,
                                    "Item": item,
                                    "WorkType": duty.isEmpty ? "FLY" : duty,
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
                                    "SDC": "", // 편 수준 SDC는 없을 수 있음
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
                                        "Duty": duty,
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

                                //currentFlightKey = fKey
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

                            // 대표 필드 보강(빈 값만 채움)
                            if (entry["AC"]?.isEmpty ?? true), !ac.isEmpty { entry["AC"] = ac }
                            if (entry["ActingRank"]?.isEmpty ?? true), !actingRank.isEmpty { entry["ActingRank"] = actingRank }
                            if (entry["WorkType"]?.isEmpty ?? true), !duty.isEmpty { entry["WorkType"] = duty }

                            // 크루 병합
                            let crewRow: [String:String] = [
                                "ActingRank": actingRank,
                                "Duty": duty,
                                "PICCode": picCode,
                                "CrewID": crewID,
                                "Name": crewName,
                                "Comment": comment,
                                "SDC": sdcPerCrew
                            ]
                            self.mergeCrewRow(crewRow, into: &entry)

                            arrForDate[pos.idx] = entry
                            newExtracted[pos.dateKey] = arrForDate
                            continue
                        }

                        // 내용 없는 빈 행은 스킵
                    }
                }

                if parsedByNewLayout, !newExtracted.isEmpty {
                    // 새 레이아웃 성공: 저장/병합
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

                        // 새 데이터 병합
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
            eventTitle = baseTitle // 제목은 기본 제목으로 설정
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
            // marker가 있다면 marker 이후의 내용을 업데이트 정보로 교체
            currentNotes = String(currentNotes[..<markerRange.upperBound]) + updatedSection
        } else {
            // marker가 없으면 기존 노트를 그대로 두고 marker와 업데이트 정보를 추가
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
        // schedules 엔트리 내 CrewList(JSON 문자열) 읽기
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
}
