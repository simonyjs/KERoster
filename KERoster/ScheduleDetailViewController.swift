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
        if let entry = metarCache[key], Date().timeIntervalSince(entry.date) < ttl { return entry.data }
        return nil
    }
    func setMETAR(_ metar: String, for key: String) { metarCache[key] = (metar, Date()) }
    
    func getTAF(for key: String) -> String? {
        if let entry = tafCache[key], Date().timeIntervalSince(entry.date) < ttl { return entry.data }
        return nil
    }
    func setTAF(_ taf: String, for key: String) { tafCache[key] = (taf, Date()) }
    
    func clearCache() { metarCache.removeAll(); tafCache.removeAll() }
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
            for airport in airports { airportMappingDict[airport.IATA.uppercased()] = airport.ICAO }
        } catch {
            print("ApList.json 로딩 오류: \(error)")
        }
    } else {
        print("ApList.json 파일을 찾을 수 없습니다.")
    }
}

// MARK: - IATA → ICAO 변환
func convertIATAToICAO(_ iata: String) -> String? {
    if airportMappingDict.isEmpty { loadAirportMapping() }
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
    guard let icao = convertIATAToICAO(airportCode) else { completion(nil); return }
    let urlString = "https://aviationweather.gov/api/data/airport?ids=\(icao)&format=json"
    guard let url = URL(string: urlString) else { completion(nil); return }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, _, error in
        if let error = error { print("Airport Info 요청 오류: \(error.localizedDescription)"); completion(nil); return }
        guard let data = data else { completion(nil); return }
        do {
            let airportInfos = try JSONDecoder().decode([AirportInfoData].self, from: data)
            if let first = airportInfos.first {
                completion("\(first.name), \(first.country)")
            } else { completion(nil) }
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
        if elementName == "raw_text" { capturing = true; textBuffer = "" }
        else if elementName == "flight_category" { capturingFlightCategory = true; flightCategoryBuffer = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { textBuffer += string }
        if capturingFlightCategory { flightCategoryBuffer += string }
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
    guard let icao = convertIATAToICAO(airportCode) else { completion(nil); return }
    let urlString = "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=xml&taf=false"
    guard let url = URL(string: urlString) else { completion(nil); return }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, _, error in
        if let error = error { print("Detailed METAR 요청 오류: \(error.localizedDescription)"); completion(nil); return }
        guard let data = data else { completion(nil); return }
        let parserDelegate = AWCXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        if parser.parse() {
            completion((parserDelegate.foundText, parserDelegate.flightCategory))
        } else {
            print("Detailed METAR XML 파싱 실패"); completion(nil)
        }
    }.resume()
}

// MARK: - 공항 헤더 정보
func fetchHeaderInfo(for airportCode: String, completion: @escaping (String) -> Void) {
    fetchDetailedMETAR(for: airportCode) { result in
        fetchAirportInfo(for: airportCode) { airportInfo in
            let flightCat = result?.flightCategory ?? "N/A"
            let weatherEmoji = (flightCat == "VFR") ? "☀️" : "☁️"
            let info = airportInfo ?? "N/A"
            completion("[\(airportCode)] \(weatherEmoji) \(flightCat) 🎯 \(info)")
        }
    }
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
        button.setTitleColor(UIColor(named: "Ocean"), for: .normal)
        button.layer.cornerRadius = 8
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.modalPresentationStyle = .automatic
        self.title = selectedDate.isEmpty ? "Detail Schedule Info" : "Detail Schedule Info (\(selectedDate))"
        
        view.backgroundColor = .white
        setupTableView()
        setupCloseButton()
        
        // TODAY 버튼
        let todayButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = " TODAY "
        config.baseBackgroundColor = UIColor(named: "LightRed")
        config.baseForegroundColor = UIColor(named: "LightWhite")
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
            navigationController?.navigationBar.barTintColor = UIColor(named: "Ocean")
            navigationController?.navigationBar.isTranslucent = false
            navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
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
        var additionalHeight: CGFloat = 20
        if UIDevice.current.userInterfaceIdiom == .pad {
            additionalHeight += closeButton.frame.height + 10
        }
        self.preferredContentSize = CGSize(width: self.view.frame.width,
                                           height: tableView.contentSize.height + additionalHeight)
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
    @objc func closeTapped() { dismiss(animated: true, completion: nil) }
    
    // MARK: - TableView
    func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc func refreshData(_ sender: UIRefreshControl) {
        WeatherDataCache.shared.clearCache()
        displayedWeatherKeys.removeAll()
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
            if let A = f.date(from: da), let B = f.date(from: db) { return A < B }
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
            if WeatherDataCache.shared.getMETAR(for: code) == nil { fetchMETAR(for: code) { _ in } }
            if WeatherDataCache.shared.getTAF(for: code) == nil { fetchTAF(for: code) { _ in } }
        }
    }
    
    // MARK: - METAR/TAF
    func fetchMETAR(for airportCode: String, completion: @escaping (String?) -> Void) {
        guard let icao = convertIATAToICAO(airportCode) else { completion(nil); return }
        if let cached = WeatherDataCache.shared.getMETAR(for: icao) { completion(cached); return }
        let urlString = "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=xml&taf=false"
        guard let url = URL(string: urlString) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { print("METAR 요청 오류: \(error.localizedDescription)"); completion(nil); return }
            guard let data = data else { completion(nil); return }
            let parserDelegate = AWCXMLParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = parserDelegate
            if parser.parse(), let metarText = parserDelegate.foundText {
                WeatherDataCache.shared.setMETAR(metarText, for: icao)
                completion(metarText)
            } else { print("METAR XML 파싱 실패"); completion(nil) }
        }.resume()
    }
    
    func fetchTAF(for airportCode: String, completion: @escaping (String?) -> Void) {
        guard let icao = convertIATAToICAO(airportCode) else { completion(nil); return }
        if let cached = WeatherDataCache.shared.getTAF(for: icao) { completion(cached); return }
        let urlString = "https://aviationweather.gov/api/data/taf?ids=\(icao)&format=xml&metar=false&time=valid"
        guard let url = URL(string: urlString) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { print("TAF 요청 오류: \(error.localizedDescription)"); completion(nil); return }
            guard let data = data else { completion(nil); return }
            let parserDelegate = AWCXMLParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = parserDelegate
            if parser.parse(), var tafText = parserDelegate.foundText {
                let tokens = ["BECMG", "FM", "TEMPO", "PROB", "NOSIG"]
                for t in tokens { tafText = tafText.replacingOccurrences(of: " \(t)", with: "\n\(t)") }
                WeatherDataCache.shared.setTAF(tafText, for: icao)
                completion(tafText)
            } else { print("TAF XML 파싱 실패"); completion(nil) }
        }.resume()
    }
    
    // MARK: - Crew List 복원
    private func decodeCrewList(from schedule: [String:String]) -> [[String:String]]? {
        if let json = schedule["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty { return arr }
        return fetchCrewListFromGlobal(date: schedule["DepDate"] ?? "",
                                       item: schedule["Item"] ?? "",
                                       dep: schedule["DepAp"] ?? "",
                                       arr: schedule["ArrAp"] ?? "")
    }
    private func fetchCrewListFromGlobal(date: String, item: String, dep: String, arr: String) -> [[String:String]]? {
        guard let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
              let data = shared.data(forKey: schedulesUserDefaultsKey),
              let global = try? JSONDecoder().decode([String:[[String:String]]].self, from: data),
              let day = global[date] else { return nil }
        if let idx = day.firstIndex(where: { ($0["Item"] ?? "") == item && ($0["DepAp"] ?? "") == dep && ($0["ArrAp"] ?? "") == arr }),
           let json = day[idx]["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty { return arr }
        if let idx = day.firstIndex(where: { ($0["Item"] ?? "") == item }),
           let json = day[idx]["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty { return arr }
        if let last = day.last,
           let json = last["CrewList"]?.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: json, options: []) as? [[String:String]],
           !arr.isEmpty { return arr }
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
        let title = "🧑‍✈️ \(symbol) Crew List (\(count))\n"
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
        // 실제 데이터 키와 화면 표시 이름 매핑 (요청한 라벨 변경)
        var displayHeaders: [(key: String, title: String)] = [
            ("Name", "Name"),
            ("CrewID", "ID NO."),
            ("WorkType", "Type"),
            ("PostingRank", "Rank"),
            ("PICCode", "Code"),
            ("Contact", "Contact")
        ]
        // Role: 값이 있으면 추가
        let hasRole = crew.contains { ($0["Role"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        if hasRole { displayHeaders.append(("Role", "Role")) }
        // SDC: 값이 있으면 추가
        let hasSDC = crew.contains { ($0["SDC"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        if hasSDC { displayHeaders.append(("SDC", "SDC")) }
        
        // 각 컬럼 폭 계산 (헤더/셀 모두 고려)
        var widths: [Int] = displayHeaders.map { $0.title.count }
        for row in crew {
            for (i, h) in displayHeaders.enumerated() {
                let val = (row[h.key] ?? "").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
                widths[i] = max(widths[i], val.count)
            }
        }
        let maxColWidth = 24
        widths = widths.map { min($0, maxColWidth) }
        
        func hLine(left: String, mid: String, right: String, fill: String = "─", widths: [Int]) -> String {
            let parts = widths.map { String(repeating: Character(fill), count: $0 + 2) } // 좌우 1칸 여백
            return left + parts.joined(separator: mid) + right
        }
        let top    = hLine(left: " ", mid: " ", right: " ", widths: widths)
        let midSep = hLine(left: " ", mid: " ", right: " ", widths: widths)
        let bottom = hLine(left: " ", mid: " ", right: " ", widths: widths)
        
        let headerRow = " " + zip(displayHeaders, widths).map { " " + pad($0.title, to: $1) + " " }.joined(separator: " ") + " "
        let dataRows = crew.map { row in
            " " + zip(displayHeaders, widths).map {
                let raw = (row[$0.key] ?? "").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: " ", with: " ")
                return " " + pad(raw, to: $1) + " "
            }.joined(separator: " ") + " "
        }
        let tableLines = [top, headerRow, midSep] + dataRows + [bottom]
        _ = tableLines.joined(separator: "\n") + "\n"
        
        // 스타일
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
        let fontRegular = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        let fontBold    = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
        
        // 우선 텍스트로 구성
        let fullAttr = NSMutableAttributedString()
        fullAttr.append(NSAttributedString(string: top + "\n", attributes: [.font: fontRegular, .foregroundColor: UIColor.label, .paragraphStyle: para]))
        fullAttr.append(NSAttributedString(string: headerRow + "\n", attributes: [.font: fontBold,   .foregroundColor: UIColor.label, .paragraphStyle: para]))
        fullAttr.append(NSAttributedString(string: midSep + "\n", attributes: [.font: fontRegular, .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: para]))
        for (i, r) in dataRows.enumerated() {
            fullAttr.append(NSAttributedString(string: r + "\n", attributes: [.font: fontRegular, .foregroundColor: UIColor.label, .paragraphStyle: para]))
            if i == dataRows.count - 1 {
                fullAttr.append(NSAttributedString(string: bottom + "\n", attributes: [.font: fontRegular, .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: para]))
            }
        }
        
        // 폭 체크 → 좁으면 이미지 폴백
        let maxContentWidth = self.view?.bounds.width ?? UIScreen.main.bounds.width
        let horizontalPadding: CGFloat = 32
        let limitWidth = max(200, maxContentWidth - horizontalPadding)
        
        let longestLine = tableLines.max(by: { $0.count < $1.count }) ?? ""
        let lineSize = (longestLine as NSString).size(withAttributes: [.font: fontRegular])
        let needFallbackToImage = (lineSize.width > limitWidth)
        
        if !needFallbackToImage {
            // 그대로 텍스트 사용
            return fullAttr
        }
        
        // 이미지 렌더링 폴백
        let maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let bounding = fullAttr.boundingRect(with: maxSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral
        let imageSize = CGSize(width: min(bounding.width + 8, 8000), height: bounding.height + 8)
        
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: UIGraphicsImageRendererFormat.default())
        let image = renderer.image { _ in
            UIColor.systemBackground.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()
            let drawRect = CGRect(x: 4, y: 4, width: imageSize.width - 8, height: imageSize.height - 8)
            fullAttr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
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
        
        let defaultFont = isToday ? UIFont.systemFont(ofSize: 21) : UIFont.systemFont(ofSize: 14)
        let boldFont = isToday ? UIFont.boldSystemFont(ofSize: 30) : UIFont.boldSystemFont(ofSize: 20)
        let textColor: UIColor = isToday ? (UIColor(named: "LightDark") ?? .black) : UIColor.label
        
        let att = NSMutableAttributedString()
        let workType = details["WorkType"] ?? "N/A"
        
        if workType == "FLY" || workType == "TVL" {
            var item = details["Item"] ?? "N/A"
            let depAp = details["DepAp"] ?? "N/A"
            let depTimeLocal = details["DepStnTime"] ?? "N/A"
            let arrAp = details["ArrAp"] ?? "N/A"
            let arrTimeLocal = details["ArrStnTime"] ?? "N/A"
            let flyingHours = details["FlyingHours"] ?? "N/A"
            let dutyHours = details["DutyHours"] ?? "N/A"
            
            let transportIcon = (workType == "FLY") ? "✈️" : "📌"
            if workType == "TVL", !item.isEmpty { item = "DH" + item.dropFirst(2) }
            
            let dateLine = depDateFormatted == arrDateFormatted ? "📅 \(depDateFormatted)" : "📅 \(depDateFormatted) ~ \(arrDateFormatted)"
            att.append(NSAttributedString(string: dateLine, attributes: [.font: defaultFont, .foregroundColor: textColor]))
            att.append(NSAttributedString(string: "\n\(transportIcon) ", attributes: [.font: defaultFont, .foregroundColor: textColor]))
            att.append(NSAttributedString(string: item, attributes: [.font: boldFont, .foregroundColor: textColor]))
            
            var detailsLine = "\n📍 \(depTimeLocal) \(depAp) - \(arrTimeLocal) \(arrAp)\n⏳ FLT TIME: \(flyingHours)\n⌛ DUTY HOURS: \(dutyHours)"
            if let hotel = details["Hotel"], !hotel.isEmpty { detailsLine += "\n🏨 Hotel: \(hotel)" }
            att.append(NSAttributedString(string: detailsLine, attributes: [.font: defaultFont, .foregroundColor: textColor]))
        } else {
            let activity = details["Activity"] ?? "N/A"
            let dutyReport = details["DutyReport"] ?? "N/A"
            let dutyDebrief = details["DutyDebrief"] ?? "N/A"
            var pureDutyDebrief = dutyDebrief
            if let parenIndex = dutyDebrief.firstIndex(of: "(") { pureDutyDebrief = String(dutyDebrief[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines) }
            
            if let dutyDebriefDateStr = details["DutyDebriefDate"], dutyDebriefDateStr != (details["DepDate"] ?? "") {
                let dutyDebriefFormatted = inputFormatter.date(from: dutyDebriefDateStr).flatMap { outputFormatter.string(from: $0) } ?? dutyDebriefDateStr
                att.append(NSAttributedString(string: "📅 \(depDateFormatted) ~ \(dutyDebriefFormatted)\n", attributes: [.font: defaultFont, .foregroundColor: textColor]))
            } else {
                att.append(NSAttributedString(string: "📅 \(depDateFormatted)\n", attributes: [.font: defaultFont, .foregroundColor: textColor]))
            }
            let icon = (activity == "DO") ? "🏠" : "🏢"
            att.append(NSAttributedString(string: "\(icon) ", attributes: [.font: defaultFont, .foregroundColor: textColor]))
            att.append(NSAttributedString(string: activity, attributes: [.font: boldFont, .foregroundColor: textColor]))
            att.append(NSAttributedString(string: " : \(dutyReport) - \(pureDutyDebrief)", attributes: [.font: defaultFont, .foregroundColor: textColor]))
        }
        return att
    }
    
    // MARK: - 비행 추가정보(크루 토글 + 표 + 날씨)
    func fetchFlightAdditionalInfo(for schedule: [String: String],
                                   indexPath: IndexPath,
                                   baseText: NSAttributedString,
                                   displayFont: UIFont,
                                   allowDuplicateUpdate: Bool = false) {
        guard let depAp = schedule["DepAp"], let arrAp = schedule["ArrAp"] else { return }
        let dateKey = schedule["DepDate"] ?? selectedDate
        let sortedAirports = [depAp, arrAp].map { $0.uppercased() }.sorted()
        let weatherKey = "\(dateKey)_\(sortedAirports[0])_\(sortedAirports[1])"
        
        if !allowDuplicateUpdate, displayedWeatherKeys.contains(weatherKey) { return }
        displayedWeatherKeys.insert(weatherKey)
        
        // Crew 준비
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
                
                // --- 크루 토글 라인/테이블 (DUTY HOURS 다음 줄에) ---
                if let crewArray = crewArray {
                    combined.append(NSAttributedString(string: "\n")) // Duty Hours와 시각적 분리
                    let toggleLine = self.makeCrewToggleLine(expanded: isExpanded, count: crewCount, font: displayFont)
                    combined.append(toggleLine)
                    if isExpanded {
                        combined.append(self.makeCrewListAttributed(crewArray, font: displayFont))
                    }
                }
                
                // --- 날씨 블록 ---
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
                let weatherAttr = NSAttributedString(string: weatherText,
                                                     attributes: [.font: UIFont.systemFont(ofSize: 12),
                                                                  .foregroundColor: UIColor.systemGreen])
                
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
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let details = scheduleDetailsList[indexPath.row]
        
        // 오늘 여부
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        let isToday: Bool = {
            if let depDateStr = details["DepDate"], let scheduleDate = inputFormatter.date(from: depDateStr) {
                return Calendar.current.isDate(scheduleDate, inSameDayAs: Date())
            }
            return false
        }()
        
        // 배경/폰트
        cell.backgroundColor = isToday ? UIColor(named: "LightYellow") : .clear
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        
        // DUTY HOURS와 동일 크기 폰트
        let defaultFont = isToday ? UIFont.systemFont(ofSize: 21) : UIFont.systemFont(ofSize: 14)
        
        // 베이스 텍스트(스케줄 본문)
        let baseText = buildBaseText(for: details, isToday: isToday)
        cell.textLabel?.attributedText = baseText
        
        // 비행이면 추가정보 붙이기(같은 공항쌍의 마지막 셀만)
        let workType = details["WorkType"] ?? "N/A"
        if workType == "FLY" || workType == "TVL" {
            if shouldDisplayWeather(for: details, at: indexPath.row) {
                fetchFlightAdditionalInfo(for: details,
                                          indexPath: indexPath,
                                          baseText: baseText,
                                          displayFont: defaultFont,
                                          allowDuplicateUpdate: false)
            }
        }
        return cell
    }
    
    private func shouldDisplayWeather(for details: [String:String], at row: Int) -> Bool {
        let dateKey = details["DepDate"] ?? selectedDate
        guard let depAp = details["DepAp"], let arrAp = details["ArrAp"] else { return false }
        let pair = Set([depAp.uppercased(), arrAp.uppercased()])
        if let lastIndexForGroup = scheduleDetailsList.lastIndex(where: { s in
            guard let d = s["DepDate"], let a = s["DepAp"], let b = s["ArrAp"] else { return false }
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
        
        // FLY/TVL일 때 토글 우선
        if workType == "FLY" || workType == "TVL" {
            guard let depAp = schedule["DepAp"], let arrAp = schedule["ArrAp"] else {
                // 편집 이동
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
                if expandedCrewKeys.contains(weatherKey) { expandedCrewKeys.remove(weatherKey) }
                else { expandedCrewKeys.insert(weatherKey) }
                
                // 재그리기
                let isToday2: Bool = {
                    let f = DateFormatter(); f.dateFormat = "dd-MMM-yyyy"; f.locale = Locale(identifier: "en_US_POSIX")
                    if let depDateStr = schedule["DepDate"], let d = f.date(from: depDateStr) {
                        return Calendar.current.isDate(d, inSameDayAs: Date())
                    }
                    return false
                }()
                let displayFont = isToday2 ? UIFont.systemFont(ofSize: 21) : UIFont.systemFont(ofSize: 14)
                let base = buildBaseText(for: schedule, isToday: isToday2)
                if let cell = tableView.cellForRow(at: indexPath) {
                    cell.textLabel?.attributedText = base
                }
                // 중복방지 무시하고 강제 갱신
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
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (_, _, completion) in
            guard let self = self else { return }
            self.scheduleDetailsList.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            self.updateGlobalSchedulesFromDetails()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    // MARK: - ScheduleEditDelegate
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String : String], at index: Int) {
        scheduleDetailsList[index] = schedule
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        updateGlobalSchedulesFromDetails()
    }
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int) {
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
            do { globalSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data) }
            catch { print("글로벌 스케줄 로드 실패: \(error)") }
        }
        var updatedGroup: [String: [[String: String]]] = [:]
        let f = DateFormatter(); f.dateFormat = "dd-MMM-yyyy"; f.locale = Locale(identifier: "en_US_POSIX")
        for schedule in scheduleDetailsList { if let d = schedule["DepDate"] { updatedGroup[d, default: []].append(schedule) } }
        
        let mf = DateFormatter(); mf.dateFormat = "MMM yyyy"; mf.locale = Locale(identifier: "en_US_POSIX")
        let selectedMonth = selectedDate
        for key in globalSchedules.keys {
            if let date = f.date(from: key) {
                let keyMonth = mf.string(from: date)
                if keyMonth == selectedMonth {
                    if let newValue = updatedGroup[key] { globalSchedules[key] = newValue; updatedGroup.removeValue(forKey: key) }
                    else { globalSchedules.removeValue(forKey: key) }
                }
            }
        }
        for (key, value) in updatedGroup {
            if let date = f.date(from: key) {
                let keyMonth = mf.string(from: date)
                if keyMonth == selectedMonth { globalSchedules[key] = value }
            }
        }
        do {
            let encoded = try JSONEncoder().encode(globalSchedules)
            if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
                sharedDefaults.set(encoded, forKey: schedulesUserDefaultsKey); sharedDefaults.synchronize()
            }
            print("글로벌 스케줄 저장 성공")
        } catch { print("글로벌 스케줄 저장 실패: \(error)") }
    }
    
    // MARK: - 도우미
    func printSchedulesToConsole() {
        if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
           let data = shared.data(forKey: schedulesUserDefaultsKey),
           let global = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
            print("----- 저장된 스케줄 출력 -----")
            for (date, entries) in global { print("날짜: \(date)"); for e in entries { print("스케줄: \(e)") } }
            print("----- 출력 완료 -----")
        } else { print("글로벌 스케줄 데이터가 없습니다.") }
    }
    
    func indexForTodayOrNearest() -> IndexPath? {
        let today = Date()
        let f = DateFormatter(); f.dateFormat = "dd-MMM-yyyy"; f.locale = Locale(identifier: "en_US_POSIX")
        var nearest: Int?
        for (idx, s) in scheduleDetailsList.enumerated() {
            if let dateString = s["DepDate"], let d = f.date(from: dateString) {
                if Calendar.current.isDate(d, inSameDayAs: today) { return IndexPath(row: idx, section: 0) }
                if d > today, nearest == nil { nearest = idx }
            }
        }
        if let i = nearest { return IndexPath(row: i, section: 0) }
        if !scheduleDetailsList.isEmpty { return IndexPath(row: scheduleDetailsList.count - 1, section: 0) }
        return nil
    }
    
    @objc func scrollToToday() {
        if let indexPath = indexForTodayOrNearest() {
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        } else {
            let alert = UIAlertController(title: "ALERT", message: "There are no scheduled events for today or later.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}
