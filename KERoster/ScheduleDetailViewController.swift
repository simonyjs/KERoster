//  ScheduleDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/31.
//

import UIKit

// MARK: - ScheduleEditDelegate 프로토콜
protocol ScheduleEditDelegate: AnyObject {
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int)
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int)
}

// MARK: - 응답 캐싱 (TTL 1시간 적용)
class WeatherDataCache {
    static let shared = WeatherDataCache()
    private init() { }
    
    private let ttl: TimeInterval = 3600
    private var metarCache: [String: (data: String, date: Date)] = [:]
    private var tafCache: [String: (data: String, date: Date)] = [:]
    
    func getMETAR(for key: String) -> String? {
        if let entry = metarCache[key], Date().timeIntervalSince(entry.date) < ttl {
            return entry.data
        }
        return nil
    }
    func setMETAR(_ metar: String, for key: String) {
        metarCache[key] = (metar, Date())
    }
    
    func getTAF(for key: String) -> String? {
        if let entry = tafCache[key], Date().timeIntervalSince(entry.date) < ttl {
            return entry.data
        }
        return nil
    }
    func setTAF(_ taf: String, for key: String) {
        tafCache[key] = (taf, Date())
    }
    
    func clearCache() {
        metarCache.removeAll()
        tafCache.removeAll()
    }
}

// MARK: - AirportMapping 모델 (ApList.json 파일 형식)
struct AirportMapping: Codable {
    let IATA: String
    let ICAO: String
    let utc_offset: Double
    let dst: Bool
    let name: String
}

// 전역 매핑 딕셔너리 (IATA -> ICAO)
var airportMappingDict: [String: String] = [:]

// ApList.json 파일에서 매핑 정보를 로드
func loadAirportMapping() {
    if let url = Bundle.main.url(forResource: "ApList", withExtension: "json") {
        do {
            let data = try Data(contentsOf: url)
            let airports = try JSONDecoder().decode([AirportMapping].self, from: data)
            for airport in airports {
                airportMappingDict[airport.IATA.uppercased()] = airport.ICAO
            }
        } catch {
            print("ApList.json 로딩 오류: \(error)")
        }
    } else {
        print("ApList.json 파일을 찾을 수 없습니다.")
    }
}

// MARK: - IATA → ICAO 변환
func convertIATAToICAO(_ iata: String) -> String? {
    if airportMappingDict.isEmpty {
        loadAirportMapping()
    }
    return airportMappingDict[iata.uppercased()]
}

// MARK: - Airport Info JSON 모델
struct AirportInfoData: Codable {
    let icaoId: String
    let name: String
    let country: String
}

// MARK: - 공항 정보 가져오기
func fetchAirportInfo(for airportCode: String, completion: @escaping (String?) -> Void) {
    guard let icao = convertIATAToICAO(airportCode) else {
        completion(nil)
        return
    }
    let urlString = "https://aviationweather.gov/api/data/airport?ids=\(icao)&format=json"
    guard let url = URL(string: urlString) else {
        completion(nil)
        return
    }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, _, error in
        if let error = error {
            print("Airport Info 요청 오류: \(error.localizedDescription)")
            completion(nil)
            return
        }
        guard let data = data else {
            completion(nil)
            return
        }
        do {
            let airportInfos = try JSONDecoder().decode([AirportInfoData].self, from: data)
            if let first = airportInfos.first {
                completion("\(first.name), \(first.country)")
            } else {
                completion(nil)
            }
        } catch {
            print("Airport Info JSON 파싱 오류: \(error)")
            completion(nil)
        }
    }.resume()
}

// MARK: - AWC XML Parser (raw_text / flight_category)
class AWCXMLParserDelegate: NSObject, XMLParserDelegate {
    var foundText: String?
    var flightCategory: String?
    var currentElement = ""
    var capturing = false
    var textBuffer = ""
    var capturingFlightCategory = false
    var flightCategoryBuffer = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "raw_text" {
            capturing = true
            textBuffer = ""
        } else if elementName == "flight_category" {
            capturingFlightCategory = true
            flightCategoryBuffer = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing {
            textBuffer += string
        }
        if capturingFlightCategory {
            flightCategoryBuffer += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "raw_text" {
            capturing = false
            foundText = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if elementName == "flight_category" {
            capturingFlightCategory = false
            flightCategory = flightCategoryBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - 상세 METAR
func fetchDetailedMETAR(for airportCode: String, completion: @escaping ((metarText: String?, flightCategory: String?)?) -> Void) {
    guard let icao = convertIATAToICAO(airportCode) else {
        completion(nil)
        return
    }
    let urlString = "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=xml&taf=false"
    guard let url = URL(string: urlString) else {
        completion(nil)
        return
    }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, _, error in
        if let error = error {
            print("Detailed METAR 요청 오류: \(error.localizedDescription)")
            completion(nil)
            return
        }
        guard let data = data else {
            completion(nil)
            return
        }
        let parserDelegate = AWCXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        if parser.parse() {
            completion((parserDelegate.foundText, parserDelegate.flightCategory))
        } else {
            print("Detailed METAR XML 파싱 실패")
            completion(nil)
        }
    }.resume()
}

// MARK: - 공항 헤더 정보 (날씨 이모지 유지)
func fetchHeaderInfo(for airportCode: String, completion: @escaping (String) -> Void) {
    fetchDetailedMETAR(for: airportCode) { result in
        fetchAirportInfo(for: airportCode) { airportInfo in
            let flightCat = (result?.flightCategory ?? "N/A").uppercased()
            
            let weatherEmoji: String
            switch flightCat {
            case "VFR":
                weatherEmoji = "☀️"
            case "MVFR":
                weatherEmoji = "🌤️"
            case "IFR":
                weatherEmoji = "☁️"
            case "LIFR":
                weatherEmoji = "🌧️"
            default:
                weatherEmoji = "☁️"
            }
            
            let info = airportInfo ?? "N/A"
            completion("[\(airportCode)] \(weatherEmoji) \(flightCat) - \(info)")
        }
    }
}

// MARK: - 고정 팔레트 (다크/라이트 무시)
private enum ScheduleDetailPalette {
    static let lightRed = UIColor(red: 0.98, green: 0.68, blue: 0.68, alpha: 1.0)
    static let lightBlue = UIColor(red: 0.88, green: 0.95, blue: 0.98, alpha: 1.0)
    static let lightYellow = UIColor(red: 1.0, green: 0.98, blue: 0.75, alpha: 1.0)
    static let ocean = UIColor(red: 0.00, green: 0.48, blue: 0.71, alpha: 1.0)
}

// MARK: - ScheduleDetailViewController
class ScheduleDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, ScheduleEditDelegate {
    
    // MARK: - Properties
    var scheduleDetailsList: [[String: String]] = []
    var selectedDate: String = ""
    let tableView = UITableView()
    let schedulesUserDefaultsKey = "schedules"
    
    // 중복 날씨 표시 방지
    var displayedWeatherKeys: Set<String> = []
    // 크루리스트 접힘/펼침 키
    var expandedCrewKeys: Set<String> = []
    
    // CLOSE 버튼 – 모달일 때만 보임
    let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("CLOSE", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .white
        button.setTitleColor(ScheduleDetailPalette.ocean, for: .normal)
        button.layer.cornerRadius = 8
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        self.modalPresentationStyle = .automatic
        self.title = selectedDate.isEmpty ? "Detail Schedule Info" : "Detail Schedule Info (\(selectedDate))"
        
        view.backgroundColor = .white
        
        setupTableView()
        setupCloseButton()
        
        // TODAY 버튼
        let todayButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = " TODAY "
        config.baseBackgroundColor = ScheduleDetailPalette.lightRed
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
        todayButton.configuration = config
        todayButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        todayButton.configuration?.cornerStyle = .capsule
        todayButton.addTarget(self, action: #selector(scrollToToday), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: todayButton)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.presentingViewController != nil {
            closeButton.isHidden = false
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.navigationBar.barTintColor = ScheduleDetailPalette.ocean
            navigationController?.navigationBar.isTranslucent = false
            navigationController?.navigationBar.titleTextAttributes = [
                NSAttributedString.Key.foregroundColor: UIColor.white
            ]
        } else {
            closeButton.isHidden = true
        }
        displayedWeatherKeys.removeAll()
        expandedCrewKeys.removeAll()
        sortScheduleDetails()
        tableView.reloadData()
        prefetchWeatherData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let indexPath = self.indexForTodayOrNearest() {
                self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        tableView.layoutIfNeeded()
        
        // CLOSE 버튼이 tableView 위에 겹치는 높이 계산
        let overlapHeight = max(0, closeButton.frame.maxY - tableView.frame.minY)
        
        let contentHeight = tableView.contentSize.height
        var additionalHeight: CGFloat = 20   // 아래 여유
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            additionalHeight += 10           // iPad에서 여유 조금 더
        }
        
        let rawHeight = contentHeight + additionalHeight - overlapHeight
        
        let screenH = UIScreen.main.bounds.height
        let minH = screenH * 0.05
        let maxH = screenH * 0.9
        let finalH = max(minH, min(rawHeight, maxH))
        
        self.preferredContentSize = CGSize(width: self.view.frame.width,
                                           height: finalH)
    }

    
    // MARK: - CLOSE 버튼
    func setupCloseButton() {
        view.addSubview(closeButton)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 60),
            closeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    @objc func closeTapped() {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: - TableView
    func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()
        tableView.separatorStyle = .none
        
        // 셀 사이 간격이 흰색으로 보이도록
        tableView.backgroundColor = .white
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            // 1일 위 빈 여백 제거
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        view.bringSubviewToFront(closeButton)
    }
    
    @objc func refreshData(_ sender: UIRefreshControl) {
        WeatherDataCache.shared.clearCache()
        displayedWeatherKeys.removeAll()
        expandedCrewKeys.removeAll()
        prefetchWeatherData()
        sortScheduleDetails()
        tableView.reloadData()
        sender.endRefreshing()
    }
    
    // MARK: - 정렬
    func sortScheduleDetails() {
        let f = DateFormatter()
        f.dateFormat = "dd-MMM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        scheduleDetailsList.sort { a, b in
            let da = a["DepDate"] ?? selectedDate
            let db = b["DepDate"] ?? selectedDate
            if let A = f.date(from: da), let B = f.date(from: db) {
                return A < B
            }
            return da < db
        }
    }
    
    // MARK: - 미리 가져오기
    func prefetchWeatherData() {
        var airportCodes = Set<String>()
        for schedule in scheduleDetailsList {
            if let workType = schedule["WorkType"], (workType == "FLY" || workType == "TVL") {
                if let depAp = schedule["DepAp"], !depAp.isEmpty { airportCodes.insert(depAp) }
                if let arrAp = schedule["ArrAp"], !arrAp.isEmpty { airportCodes.insert(arrAp) }
            }
        }
        for code in airportCodes {
            if WeatherDataCache.shared.getMETAR(for: code) == nil {
                fetchMETAR(for: code) { _ in }
            }
            if WeatherDataCache.shared.getTAF(for: code) == nil {
                fetchTAF(for: code) { _ in }
            }
        }
    }
    
    // MARK: - METAR/TAF
    func fetchMETAR(for airportCode: String, completion: @escaping (String?) -> Void) {
        guard let icao = convertIATAToICAO(airportCode) else {
            completion(nil)
            return
        }
        if let cached = WeatherDataCache.shared.getMETAR(for: icao) {
            completion(cached)
            return
        }
        let urlString = "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=xml&taf=false"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("METAR 요청 오류: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else {
                completion(nil)
                return
            }
            let parserDelegate = AWCXMLParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = parserDelegate
            if parser.parse(), let metarText = parserDelegate.foundText {
                WeatherDataCache.shared.setMETAR(metarText, for: icao)
                completion(metarText)
            } else {
                print("METAR XML 파싱 실패")
                completion(nil)
            }
        }.resume()
    }
    
    func fetchTAF(for airportCode: String, completion: @escaping (String?) -> Void) {
        guard let icao = convertIATAToICAO(airportCode) else {
            completion(nil)
            return
        }
        if let cached = WeatherDataCache.shared.getTAF(for: icao) {
            completion(cached)
            return
        }
        let urlString = "https://aviationweather.gov/api/data/taf?ids=\(icao)&format=xml&metar=false&time=valid"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("TAF 요청 오류: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else {
                completion(nil)
                return
            }
            let parserDelegate = AWCXMLParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = parserDelegate
            if parser.parse(), var tafText = parserDelegate.foundText {
                let tokens = ["BECMG", "FM", "TEMPO", "PROB", "NOSIG"]
                for t in tokens {
                    tafText = tafText.replacingOccurrences(of: " \(t)", with: "\n\(t)")
                }
                WeatherDataCache.shared.setTAF(tafText, for: icao)
                completion(tafText)
            } else {
                print("TAF XML 파싱 실패")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - Crew List 복원
    private func decodeCrewList(from schedule: [String:String]) -> [[String:String]]? {
        // 1) 스케줄 자체에 저장된 CrewList 우선
        if let json = schedule["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty {
            return arr
        }

        // 2) 폴백은 FLY/TVL에서만 허용 (비행 아닌 WT에는 붙이지 않음)
        let wt = (schedule["WorkType"] ?? "").uppercased()
        guard wt == "FLY" || wt == "TVL" else { return nil }

        return fetchCrewListFromGlobal(date: schedule["DepDate"] ?? "",
                                       item: schedule["Item"] ?? "",
                                       dep: schedule["DepAp"] ?? "",
                                       arr: schedule["ArrAp"] ?? "")
    }

    // 비행이 아닌 항목용: row 기준으로 유니크 키
    private func crewKeyNonFlight(for schedule: [String:String], indexPath: IndexPath) -> String {
        let dateKey = schedule["DepDate"] ?? selectedDate
        let activity = (schedule["Activity"] ?? schedule["Item"] ?? "NA").uppercased()
        return "CREW_NF_\(dateKey)_\(activity)_\(indexPath.row)"
    }

    private func applyCrewBlockIfNeeded(to cell: UITableViewCell,
                                       schedule: [String:String],
                                       indexPath: IndexPath,
                                       baseText: NSAttributedString,
                                       displayFont: UIFont) {

        guard let crewArray = decodeCrewList(from: schedule) else { return }

        let key = crewKeyNonFlight(for: schedule, indexPath: indexPath)
        let isExpanded = expandedCrewKeys.contains(key)

        let combined = NSMutableAttributedString(attributedString: baseText)
        combined.append(NSAttributedString(string: "\n"))
        combined.append(makeCrewToggleLine(expanded: isExpanded,
                                           count: crewArray.count,
                                           font: displayFont))
        if isExpanded {
            combined.append(makeCrewListAttributed(crewArray, font: displayFont))
        }

        cell.textLabel?.attributedText = combined
    }

    
    private func fetchCrewListFromGlobal(date: String, item: String, dep: String, arr: String) -> [[String:String]]? {
        guard let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
              let data = shared.data(forKey: schedulesUserDefaultsKey),
              let global = try? JSONDecoder().decode([String:[[String:String]]].self, from: data),
              let day = global[date] else {
            return nil
        }
        if let idx = day.firstIndex(where: { ($0["Item"] ?? "") == item && ($0["DepAp"] ?? "") == dep && ($0["ArrAp"] ?? "") == arr }),
           let json = day[idx]["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty {
            return arr
        }
        if let idx = day.firstIndex(where: { ($0["Item"] ?? "") == item }),
           let json = day[idx]["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty {
            return arr
        }
        if let last = day.last,
           let json = last["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty {
            return arr
        }
        return nil
    }
    
    // MARK: - 유틸(패딩/토글 라인)
    private func pad(_ s: String, to width: Int) -> String {
        let count = s.count
        if count == width { return s }
        if count < width { return s + String(repeating: " ", count: width - count) }
        return width > 1 ? String(s.prefix(max(0, width-1))) + "…" : String(s.prefix(width))
    }
    
    private func makeCrewToggleLine(expanded: Bool, count: Int, font: UIFont) -> NSAttributedString {
        let symbol = expanded ? "▼" : "▶"
        let title = "\(symbol) Crew List (\(count))\n"
        return NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.systemBlue
            ]
        )
    }
    
    // MARK: - 엑셀 표 느낌(헤더 라벨 변경 + Role/SDC 조건부 + 좁은 화면 이미지 폴백)
    private func makeCrewListAttributed(_ crew: [[String:String]], font: UIFont) -> NSAttributedString {
        var displayHeaders: [(key: String, title: String)] = [
            ("Name", "Name"),
            ("CrewID", "ID NO."),
            ("WorkType", "Type"),
            ("PostingRank", "Rank"),
            ("PICCode", "Code"),
            ("Contact", "Contact")
        ]
        let hasRole = crew.contains { ($0["Role"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        if hasRole { displayHeaders.append(("Role", "Role")) }
        let hasSDC = crew.contains { ($0["SDC"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        if hasSDC { displayHeaders.append(("SDC", "SDC")) }
        
        var widths: [Int] = displayHeaders.map { $0.title.count }
        for row in crew {
            for (i, h) in displayHeaders.enumerated() {
                let val = (row[h.key] ?? "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "/")
                widths[i] = max(widths[i], val.count)
            }
        }
        let maxColWidth = 24
        widths = widths.map { min($0, maxColWidth) }
        
        func hLine(left: String, mid: String, right: String, fill: String = "─", widths: [Int]) -> String {
            let parts = widths.map { String(repeating: Character(fill), count: $0 + 2) }
            return left + parts.joined(separator: mid) + right
        }
        let top    = hLine(left: " ", mid: " ", right: " ", widths: widths)
        let midSep = hLine(left: " ", mid: " ", right: " ", widths: widths)
        let bottom = hLine(left: " ", mid: " ", right: " ", widths: widths)
        
        let headerRow = " " + zip(displayHeaders, widths).map { " " + pad($0.title, to: $1) + " " }.joined(separator: " ") + " "
        let dataRows = crew.map { row in
            " " + zip(displayHeaders, widths).map {
                let raw = (row[$0.key] ?? "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: " ", with: " ")
                return " " + pad(raw, to: $1) + " "
            }.joined(separator: " ") + " "
        }
        let tableLines = [top, headerRow, midSep] + dataRows + [bottom]
        _ = tableLines.joined(separator: "\n") + "\n"
        
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let fontRegular = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        let fontBold    = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
        
        let fullAttr = NSMutableAttributedString()
        fullAttr.append(NSAttributedString(string: top + "\n",
                                           attributes: [.font: fontRegular,
                                                        .foregroundColor: UIColor.black,
                                                        .paragraphStyle: para]))
        fullAttr.append(NSAttributedString(string: headerRow + "\n",
                                           attributes: [.font: fontBold,
                                                        .foregroundColor: UIColor.black,
                                                        .paragraphStyle: para]))
        fullAttr.append(NSAttributedString(string: midSep + "\n",
                                           attributes: [.font: fontRegular,
                                                        .foregroundColor: UIColor.darkGray,
                                                        .paragraphStyle: para]))
        for (i, r) in dataRows.enumerated() {
            fullAttr.append(NSAttributedString(string: r + "\n",
                                               attributes: [.font: fontRegular,
                                                            .foregroundColor: UIColor.black,
                                                            .paragraphStyle: para]))
            if i == dataRows.count - 1 {
                fullAttr.append(NSAttributedString(string: bottom + "\n",
                                                   attributes: [.font: fontRegular,
                                                                .foregroundColor: UIColor.darkGray,
                                                                .paragraphStyle: para]))
            }
        }
        
        let maxContentWidth = self.view.bounds.width
        let horizontalPadding: CGFloat = 32
        let limitWidth = max(200, maxContentWidth - horizontalPadding)
        
        let longestLine = tableLines.max(by: { $0.count < $1.count }) ?? ""
        let lineSize = (longestLine as NSString).size(withAttributes: [.font: fontRegular])
        let needFallbackToImage = (lineSize.width > limitWidth)
        
        if !needFallbackToImage {
            return fullAttr
        }
        
        let maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let bounding = fullAttr.boundingRect(with: maxSize,
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             context: nil).integral
        let imageSize = CGSize(width: min(bounding.width + 8, 8000), height: bounding.height + 8)
        
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: UIGraphicsImageRendererFormat.default())
        let image = renderer.image { _ in
            UIColor.systemBackground.setFill()
            UIColor.white.setFill()   // 핵심 수정
            UIBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()
            let drawRect = CGRect(x: 4, y: 4, width: imageSize.width - 8, height: imageSize.height - 8)
            fullAttr.draw(with: drawRect,
                          options: [.usesLineFragmentOrigin, .usesFontLeading],
                          context: nil)
        }
        let attach = NSTextAttachment()
        attach.image = image
        let imgAttr = NSAttributedString(attachment: attach)
        let result = NSMutableAttributedString()
        result.append(imgAttr)
        result.append(NSAttributedString(string: "\n"))
        return result
    }
    
    // MARK: - 베이스 텍스트(스케줄 본문)
    private func buildBaseText(for details: [String:String], isToday: Bool) -> NSAttributedString {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd"
        
        let depDateOriginal = details["DepDate"] ?? selectedDate
        let arrDateOriginal = details["ArrDate"] ?? selectedDate
        let depDateFormatted = inputFormatter.date(from: depDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? depDateOriginal
        let arrDateFormatted = inputFormatter.date(from: arrDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? arrDateOriginal
        
        // DepDate vs ArrDate 일(day) 차이 계산 (+1 / -1 표시용)
        var dayOffset: Int = 0
        if let depDate = inputFormatter.date(from: depDateOriginal),
           let arrDate = inputFormatter.date(from: arrDateOriginal) {
            let cal = Calendar(identifier: .gregorian)
            dayOffset = cal.dateComponents([.day], from: depDate, to: arrDate).day ?? 0
        }
        
        let defaultFont = isToday ? UIFont.systemFont(ofSize: 21) : UIFont.systemFont(ofSize: 14)
        let boldFont = isToday ? UIFont.boldSystemFont(ofSize: 30) : UIFont.boldSystemFont(ofSize: 20)
        let routeBoldFont = UIFont.boldSystemFont(ofSize: defaultFont.pointSize)
        let textColor: UIColor = .black
        
        let att = NSMutableAttributedString()
        let workType = details["WorkType"] ?? "N/A"
        
        if workType == "FLY" || workType == "TVL" {
            // 비행 / TVL
            var item = details["Item"] ?? "N/A"
            let depAp = details["DepAp"] ?? "N/A"
            let depTimeLocal = details["DepStnTime"] ?? "N/A"
            let arrAp = details["ArrAp"] ?? "N/A"
            let arrTimeLocal = details["ArrStnTime"] ?? "N/A"
            let flyingHours = details["FlyingHours"] ?? "N/A"
            let dutyHours = details["DutyHours"] ?? "N/A"
            
            if workType == "TVL", !item.isEmpty {
                item = "DH" + item.dropFirst(2)
            }
            
            let dateLine = (depDateFormatted == arrDateFormatted)
                ? depDateFormatted
                : "\(depDateFormatted) ~ \(arrDateFormatted)"
            att.append(NSAttributedString(
                string: dateLine + "\n",
                attributes: [.font: defaultFont, .foregroundColor: textColor]
            ))
            
            let titleLine = item.isEmpty ? "FLIGHT" : item
            att.append(NSAttributedString(
                string: titleLine + "\n",
                attributes: [.font: boldFont, .foregroundColor: textColor]
            ))
            
            // 도착 날짜가 다르면 도착시간 뒤에 (+1) / (-1) 표시
            var arrTimeWithOffset = arrTimeLocal
            if dayOffset > 0 {
                arrTimeWithOffset += " (+\(dayOffset))"
            } else if dayOffset < 0 {
                arrTimeWithOffset += " (\(dayOffset))"
            }
            
            // 노선 라인: 출발/도착 공항은 볼드, 시간은 일반
            let routeAttr = NSMutableAttributedString()
            // DEP 공항 (볼드)
            routeAttr.append(NSAttributedString(
                string: depAp,
                attributes: [.font: routeBoldFont, .foregroundColor: textColor]
            ))
            // DEP 시간 + 화살표
            routeAttr.append(NSAttributedString(
                string: " \(depTimeLocal)  →  ",
                attributes: [.font: defaultFont, .foregroundColor: textColor]
            ))
            // ARR 시간 (+1/-1 포함, 일반)
            routeAttr.append(NSAttributedString(
                string: arrTimeWithOffset + " ",
                attributes: [.font: defaultFont, .foregroundColor: textColor]
            ))
            // ARR 공항 (볼드)
            routeAttr.append(NSAttributedString(
                string: arrAp + "\n",
                attributes: [.font: routeBoldFont, .foregroundColor: textColor]
            ))
            
            att.append(routeAttr)
            
            let fhLine = "Flight Hours: \(flyingHours)"
            let dhLine = "Duty Hours:  \(dutyHours)"
            att.append(NSAttributedString(
                string: fhLine + "\n",
                attributes: [.font: defaultFont, .foregroundColor: textColor]
            ))
            att.append(NSAttributedString(
                string: dhLine,
                attributes: [.font: defaultFont, .foregroundColor: textColor]
            ))
            
            if let hotel = details["Hotel"], !hotel.isEmpty {
                att.append(NSAttributedString(
                    string: "\nHotel: \(hotel)",
                    attributes: [.font: defaultFont, .foregroundColor: textColor]
                ))
            }
        } else {
            // 지상근무/Off 등의 Activity 케이스
            let activity = details["Activity"] ?? "N/A"
            let dutyReport = details["DutyReport"] ?? "N/A"
            let dutyDebrief = details["DutyDebrief"] ?? "N/A"
            
            var pureDutyDebrief = dutyDebrief
            if let parenIndex = dutyDebrief.firstIndex(of: "(") {
                pureDutyDebrief = String(dutyDebrief[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if let dutyDebriefDateStr = details["DutyDebriefDate"],
               dutyDebriefDateStr != (details["DepDate"] ?? "") {
                let dutyDebriefFormatted = inputFormatter.date(from: dutyDebriefDateStr).flatMap {
                    outputFormatter.string(from: $0)
                } ?? dutyDebriefDateStr
                att.append(NSAttributedString(
                    string: "\(depDateFormatted) ~ \(dutyDebriefFormatted)\n",
                    attributes: [.font: defaultFont, .foregroundColor: textColor]
                ))
            } else {
                att.append(NSAttributedString(
                    string: "\(depDateFormatted)\n",
                    attributes: [.font: defaultFont, .foregroundColor: textColor]
                ))
            }
            
            att.append(NSAttributedString(
                string: activity,
                attributes: [.font: boldFont, .foregroundColor: textColor]
            ))
            
            // 근무시간이 00:00 ~ 23:59 인 경우, 시간 표시 생략
            let isFullDayDuty =
                dutyReport.trimmingCharacters(in: .whitespacesAndNewlines) == "00:00" &&
                pureDutyDebrief.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("23:59")
            
            if !isFullDayDuty {
                att.append(NSAttributedString(
                    string: " : \(dutyReport) - \(pureDutyDebrief)",
                    attributes: [.font: defaultFont, .foregroundColor: textColor]
                ))
            }
        }
        return att
    }

    // MARK: - 비행 추가정보(크루 토글 + 표 + 날씨)
    func fetchFlightAdditionalInfo(for schedule: [String: String],
                                   indexPath: IndexPath,
                                   baseText: NSAttributedString,
                                   displayFont: UIFont,
                                   allowDuplicateUpdate: Bool = false) {
        guard let depAp = schedule["DepAp"],
              let arrAp = schedule["ArrAp"] else {
            return
        }
        let dateKey = schedule["DepDate"] ?? selectedDate
        let sortedAirports = [depAp, arrAp].map { $0.uppercased() }.sorted()
        let weatherKey = "\(dateKey)_\(sortedAirports[0])_\(sortedAirports[1])"
        
        if !allowDuplicateUpdate, displayedWeatherKeys.contains(weatherKey) {
            return
        }
        displayedWeatherKeys.insert(weatherKey)
        
        // 크루 준비
        let crewArray = decodeCrewList(from: schedule)
        let isExpanded = expandedCrewKeys.contains(weatherKey)
        let crewCount = crewArray?.count ?? 0
        
        // 날씨 비동기
        let group = DispatchGroup()
        var depMetarStr: String?
        var depTafStr: String?
        var arrMetarStr: String?
        var arrTafStr: String?
        
        group.enter(); fetchMETAR(for: depAp) { depMetarStr = $0; group.leave() }
        group.enter(); fetchTAF(for: depAp) { depTafStr = $0; group.leave() }
        group.enter(); fetchMETAR(for: arrAp) { arrMetarStr = $0; group.leave() }
        group.enter(); fetchTAF(for: arrAp) { arrTafStr = $0; group.leave() }
        
        let headerGroup = DispatchGroup()
        var depHeader: String = "[\(depAp)] N/A"
        var arrHeader: String = "[\(arrAp)] N/A"
        headerGroup.enter(); fetchHeaderInfo(for: depAp) { depHeader = $0; headerGroup.leave() }
        headerGroup.enter(); fetchHeaderInfo(for: arrAp) { arrHeader = $0; headerGroup.leave() }
        
        group.notify(queue: .main) {
            headerGroup.notify(queue: .main) {
                let combined = NSMutableAttributedString(attributedString: baseText)
                
                // --- 크루 토글 라인/테이블 (Duty Hours 다음 줄에) ---
                if let crewArray = crewArray {
                    combined.append(NSAttributedString(string: "\n"))
                    let toggleLine = self.makeCrewToggleLine(expanded: isExpanded,
                                                             count: crewCount,
                                                             font: displayFont)
                    combined.append(toggleLine)
                    if isExpanded {
                        combined.append(self.makeCrewListAttributed(crewArray, font: displayFont))
                    }
                }
                
                // --- 날씨 블록 (항상 검정 텍스트) ---
                let weatherText = """
                
                --- FLT WX INFO ---
                \(depHeader)
                METAR: \(depMetarStr ?? "N/A")
                TAF: \(depTafStr ?? "N/A")
                --- FLT WX INFO ---
                \(arrHeader)
                METAR: \(arrMetarStr ?? "N/A")
                TAF: \(arrTafStr ?? "N/A")
                """
                let weatherAttr = NSAttributedString(
                    string: weatherText,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 12),
                        .foregroundColor: UIColor.black
                    ])
                
                combined.append(weatherAttr)
                
                if let cell = self.tableView.cellForRow(at: indexPath) {
                    cell.textLabel?.attributedText = combined
                    self.tableView.beginUpdates()
                    self.tableView.endUpdates()
                    self.preferredContentSize = CGSize(width: self.view.frame.width,
                                                       height: self.tableView.contentSize.height + 20)
                }
            }
        }
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scheduleDetailsList.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let details = scheduleDetailsList[indexPath.row]
        
        // 오늘 여부
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        let isToday: Bool = {
            if let depDateStr = details["DepDate"],
               let scheduleDate = inputFormatter.date(from: depDateStr) {
                return Calendar.current.isDate(scheduleDate, inSameDayAs: Date())
            }
            return false
        }()
        
        // 배경색 (오늘: LightYellow, 나머지: LightBlue)
        let lightBlue = ScheduleDetailPalette.lightBlue
        let lightYellow = ScheduleDetailPalette.lightYellow
        cell.backgroundColor = isToday ? lightYellow : lightBlue
        
        // 기본 텍스트 설정
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        
        let defaultFont = isToday ? UIFont.systemFont(ofSize: 21) : UIFont.systemFont(ofSize: 14)
        
        // 베이스 텍스트(스케줄 본문)
        let baseText = buildBaseText(for: details, isToday: isToday)
        cell.textLabel?.attributedText = baseText
        
        // 왼쪽 바 (FLY/TVL : LightRed, 지상근무 : Ocean)
        let workType = details["WorkType"] ?? "N/A"
        
        cell.contentView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
        let barWidth: CGFloat = 4
        let bar = UIView(frame: CGRect(x: 0,
                                       y: 0,
                                       width: barWidth,
                                       height: cell.contentView.bounds.height))
        bar.autoresizingMask = [.flexibleHeight]
        bar.tag = 999
        
        if workType == "FLY" || workType == "TVL" {
            bar.backgroundColor = ScheduleDetailPalette.lightRed
        } else {
            bar.backgroundColor = ScheduleDetailPalette.ocean
        }
        cell.contentView.addSubview(bar)
        
        // 비행이면 추가정보 붙이기(같은 공항쌍의 마지막 셀만)
        if workType == "FLY" || workType == "TVL" {
            if shouldDisplayWeather(for: details, at: indexPath.row) {
                fetchFlightAdditionalInfo(for: details,
                                          indexPath: indexPath,
                                          baseText: baseText,
                                          displayFont: defaultFont,
                                          allowDuplicateUpdate: false)
            }
        } else {
            // 비행이 아니어도 CrewList가 있으면 토글/표를 붙여서 보여줌
            applyCrewBlockIfNeeded(to: cell,
                                   schedule: details,
                                   indexPath: indexPath,
                                   baseText: baseText,
                                   displayFont: defaultFont)

            // (선택) 탭은 크루 토글로 쓰고, 편집은 i 버튼으로 분리하고 싶다면:
            if decodeCrewList(from: details) != nil {
                cell.accessoryType = .detailButton
            } else {
                cell.accessoryType = .none
            }
        }

        return cell
    }
    
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let schedule = scheduleDetailsList[indexPath.row]
        let editVC = ScheduleEditViewController()
        editVC.schedule = schedule
        editVC.scheduleIndex = indexPath.row
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }

    // 셀 간격 1pt (흰색)
    func tableView(_ tableView: UITableView,
                   willDisplay cell: UITableViewCell,
                   forRowAt indexPath: IndexPath) {
        cell.contentView.subviews.filter { $0.tag == 1001 }.forEach { $0.removeFromSuperview() }
        
        let spacer = UIView(frame: CGRect(x: 0,
                                          y: cell.contentView.bounds.height - 1,
                                          width: cell.contentView.bounds.width,
                                          height: 1))
        spacer.backgroundColor = tableView.backgroundColor ?? .white
        spacer.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        spacer.tag = 1001
        cell.contentView.addSubview(spacer)
    }
    
    private func shouldDisplayWeather(for details: [String:String], at row: Int) -> Bool {
        let dateKey = details["DepDate"] ?? selectedDate
        guard let depAp = details["DepAp"], let arrAp = details["ArrAp"] else { return false }
        let pair = Set([depAp.uppercased(), arrAp.uppercased()])
        if let lastIndexForGroup = scheduleDetailsList.lastIndex(where: { s in
            guard let d = s["DepDate"],
                  let a = s["DepAp"],
                  let b = s["ArrAp"] else { return false }
            return d == dateKey && Set([a.uppercased(), b.uppercased()]) == pair
        }) {
            return lastIndexForGroup == row
        }
        return false
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        
        let schedule = scheduleDetailsList[indexPath.row]
        let workType = schedule["WorkType"] ?? "N/A"
        
        // 비행이 아닌 WT인데 CrewList가 있으면: 탭으로 토글
        if workType != "FLY" && workType != "TVL",
           decodeCrewList(from: schedule) != nil {

            let key = crewKeyNonFlight(for: schedule, indexPath: indexPath)
            if expandedCrewKeys.contains(key) { expandedCrewKeys.remove(key) }
            else { expandedCrewKeys.insert(key) }

            let isToday2: Bool = {
                let f = DateFormatter()
                f.dateFormat = "dd-MMM-yyyy"
                f.locale = Locale(identifier: "en_US_POSIX")
                if let depDateStr = schedule["DepDate"], let d = f.date(from: depDateStr) {
                    return Calendar.current.isDate(d, inSameDayAs: Date())
                }
                return false
            }()

            let displayFont = isToday2 ? UIFont.systemFont(ofSize: 21) : UIFont.systemFont(ofSize: 14)
            let base = buildBaseText(for: schedule, isToday: isToday2)

            if let cell = tableView.cellForRow(at: indexPath) {
                applyCrewBlockIfNeeded(to: cell,
                                       schedule: schedule,
                                       indexPath: indexPath,
                                       baseText: base,
                                       displayFont: displayFont)
                tableView.beginUpdates()
                tableView.endUpdates()
            }
            return
        }
    

        // FLY/TVL일 때 크루 토글 우선
        if workType == "FLY" || workType == "TVL" {
            guard let depAp = schedule["DepAp"], let arrAp = schedule["ArrAp"] else {
                let editVC = ScheduleEditViewController()
                editVC.schedule = schedule
                editVC.scheduleIndex = indexPath.row
                editVC.delegate = self
                navigationController?.pushViewController(editVC, animated: true)
                return
            }
            let dateKey = schedule["DepDate"] ?? selectedDate
            let sortedAirports = [depAp, arrAp].map { $0.uppercased() }.sorted()
            let weatherKey = "\(dateKey)_\(sortedAirports[0])_\(sortedAirports[1])"
            
            if decodeCrewList(from: schedule) != nil {
                if expandedCrewKeys.contains(weatherKey) {
                    expandedCrewKeys.remove(weatherKey)
                } else {
                    expandedCrewKeys.insert(weatherKey)
                }
                
                let isToday2: Bool = {
                    let f = DateFormatter()
                    f.dateFormat = "dd-MMM-yyyy"
                    f.locale = Locale(identifier: "en_US_POSIX")
                    if let depDateStr = schedule["DepDate"],
                       let d = f.date(from: depDateStr) {
                        return Calendar.current.isDate(d, inSameDayAs: Date())
                    }
                    return false
                }()
                let displayFont = isToday2 ? UIFont.systemFont(ofSize: 21) : UIFont.systemFont(ofSize: 14)
                let base = buildBaseText(for: schedule, isToday: isToday2)
                if let cell = tableView.cellForRow(at: indexPath) {
                    cell.textLabel?.attributedText = base
                }
                fetchFlightAdditionalInfo(for: schedule,
                                          indexPath: indexPath,
                                          baseText: base,
                                          displayFont: displayFont,
                                          allowDuplicateUpdate: true)
                return
            }
        }
        
        // 기본: 편집 화면 이동
        let editVC = ScheduleEditViewController()
        editVC.schedule = schedule
        editVC.scheduleIndex = indexPath.row
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    // 스와이프 삭제
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive,
                                              title: "Delete") { [weak self] (_, _, completion) in
            guard let self = self else { return }
            self.scheduleDetailsList.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            self.updateGlobalSchedulesFromDetails()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    // MARK: - ScheduleEditDelegate
    func scheduleEditViewController(_ controller: ScheduleEditViewController,
                                    didSaveSchedule schedule: [String : String],
                                    at index: Int) {
        scheduleDetailsList[index] = schedule
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        updateGlobalSchedulesFromDetails()
    }
    func scheduleEditViewController(_ controller: ScheduleEditViewController,
                                    didDeleteScheduleAt index: Int) {
        scheduleDetailsList.remove(at: index)
        tableView.reloadData()
        updateGlobalSchedulesFromDetails()
    }
    
    // MARK: - 글로벌 스케줄 업데이트
    func updateGlobalSchedulesFromDetails() {
        guard !selectedDate.isEmpty else { return }
        var globalSchedules: [String: [[String: String]]] = [:]
        if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
           let data = sharedDefaults.data(forKey: schedulesUserDefaultsKey) {
            do {
                globalSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            } catch {
                print("글로벌 스케줄 로드 실패: \(error)")
            }
        }
        var updatedGroup: [String: [[String: String]]] = [:]
        let f = DateFormatter()
        f.dateFormat = "dd-MMM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        for schedule in scheduleDetailsList {
            if let d = schedule["DepDate"] {
                updatedGroup[d, default: []].append(schedule)
            }
        }
        
        let mf = DateFormatter()
        mf.dateFormat = "MMM yyyy"
        mf.locale = Locale(identifier: "en_US_POSIX")
        let selectedMonth = selectedDate
        
        for key in globalSchedules.keys {
            if let date = f.date(from: key) {
                let keyMonth = mf.string(from: date)
                if keyMonth == selectedMonth {
                    if let newValue = updatedGroup[key] {
                        globalSchedules[key] = newValue
                        updatedGroup.removeValue(forKey: key)
                    } else {
                        globalSchedules.removeValue(forKey: key)
                    }
                }
            }
        }
        for (key, value) in updatedGroup {
            if let date = f.date(from: key) {
                let keyMonth = mf.string(from: date)
                if keyMonth == selectedMonth {
                    globalSchedules[key] = value
                }
            }
        }
        do {
            let encoded = try JSONEncoder().encode(globalSchedules)
            if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
                sharedDefaults.set(encoded, forKey: schedulesUserDefaultsKey)
                sharedDefaults.synchronize()
            }
            print("글로벌 스케줄 저장 성공")
        } catch {
            print("글로벌 스케줄 저장 실패: \(error)")
        }
    }
    
    // MARK: - 도우미
    func printSchedulesToConsole() {
        if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
           let data = shared.data(forKey: schedulesUserDefaultsKey),
           let global = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
            print("----- 저장된 스케줄 출력 -----")
            for (date, entries) in global {
                print("날짜: \(date)")
                for e in entries {
                    print("스케줄: \(e)")
                }
            }
            print("----- 출력 완료 -----")
        } else {
            print("글로벌 스케줄 데이터가 없습니다.")
        }
    }
    
    func indexForTodayOrNearest() -> IndexPath? {
        let today = Date()
        let f = DateFormatter()
        f.dateFormat = "dd-MMM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        var nearest: Int?
        for (idx, s) in scheduleDetailsList.enumerated() {
            if let dateString = s["DepDate"],
               let d = f.date(from: dateString) {
                if Calendar.current.isDate(d, inSameDayAs: today) {
                    return IndexPath(row: idx, section: 0)
                }
                if d > today, nearest == nil {
                    nearest = idx
                }
            }
        }
        if let i = nearest {
            return IndexPath(row: i, section: 0)
        }
        if !scheduleDetailsList.isEmpty {
            return IndexPath(row: scheduleDetailsList.count - 1, section: 0)
        }
        return nil
    }
    
    @objc func scrollToToday() {
        if let indexPath = indexForTodayOrNearest() {
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        } else {
            let alert = UIAlertController(title: "ALERT",
                                          message: "There are no scheduled events for today or later.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}
