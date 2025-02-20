//
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
    
    // TTL: 1시간 = 3600초
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
    
    // 캐시 전체 초기화 (수동 새로고침 시 사용)
    func clearCache() {
        metarCache.removeAll()
        tafCache.removeAll()
    }
}

/*
 // MARK: - AVWX API 공항 정보 응답 모델 (나중에 사용)
 struct AirportInfo: Decodable {
     let name: String
     let city: String
     let country: String
     let iata: String
     let icao: String
 }
 
 // 기존 AVWX API를 사용한 공항 정보 호출 함수는 주석 처리합니다.
 */

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

// ApList.json 파일에서 매핑 정보를 로드하는 함수
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

// MARK: - IATA → ICAO 변환 함수 (ApList.json 사용)
func convertIATAToICAO(_ iata: String) -> String? {
    if airportMappingDict.isEmpty {
        loadAirportMapping()
    }
    return airportMappingDict[iata.uppercased()]
}

// MARK: - Airport Info JSON 모델 (새로운 응답 형식: JSON 배열)
struct AirportInfoData: Codable {
    let icaoId: String
    let name: String
    let country: String
}

// MARK: - 공항 정보 가져오기 함수
func fetchAirportInfo(for airportCode: String, completion: @escaping (String?) -> Void) {
    // IATA → ICAO 변환
    guard let icao = convertIATAToICAO(airportCode) else {
        print("IATA to ICAO conversion failed for \(airportCode)")
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
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Airport Info 요청 오류: \(error.localizedDescription)")
            completion(nil)
            return
        }
        guard let data = data else { completion(nil); return }
        do {
            let airportInfos = try JSONDecoder().decode([AirportInfoData].self, from: data)
            if let first = airportInfos.first {
                let infoString = "\(first.name), \(first.country)"
                completion(infoString)
            } else {
                completion(nil)
            }
        } catch {
            print("Airport Info JSON 파싱 오류: \(error)")
            completion(nil)
        }
    }.resume()
}

// MARK: - AWC XML Parser Delegate (XML 응답에서 <raw_text> 및 <flight_category> 추출)
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

// MARK: - 상세 METAR 정보 가져오기 (원문과 flight_category 반환)
// METAR 결과는 오직 raw_text(원문)만 사용합니다.
func fetchDetailedMETAR(for airportCode: String, completion: @escaping ((metarText: String?, flightCategory: String?)?) -> Void) {
    guard let icao = convertIATAToICAO(airportCode) else {
        completion(nil)
        return
    }
    let urlString = "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=xml&taf=false"
    guard let url = URL(string: urlString) else { completion(nil); return }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, response, error in
         if let error = error {
             print("Detailed METAR 요청 오류: \(error.localizedDescription)")
             completion(nil)
             return
         }
         guard let data = data else { completion(nil); return }
         let parserDelegate = AWCXMLParserDelegate()
         let parser = XMLParser(data: data)
         parser.delegate = parserDelegate
         if parser.parse() {
             let metarText = parserDelegate.foundText
             let flightCat = parserDelegate.flightCategory
             completion((metarText, flightCat))
         } else {
             print("Detailed METAR XML 파싱 실패")
             completion(nil)
         }
    }.resume()
}

// MARK: - 공항 헤더 정보 가져오기 함수
// 헤더 형식: [공항코드] flight_category & 공항정보
func fetchHeaderInfo(for airportCode: String, completion: @escaping (String) -> Void) {
    fetchDetailedMETAR(for: airportCode) { result in
        fetchAirportInfo(for: airportCode) { airportInfo in
            let flightCat = result?.flightCategory ?? "N/A"
            // flightCat이 "VFR"이면 ☀️, 아니면 ☁️ 이모지를 사용
            let weatherEmoji = (flightCat == "VFR") ? "☀️" : "☁️"
            let info = airportInfo ?? "N/A"
            let header = "[\(airportCode)] \(weatherEmoji) \(flightCat) 🎯 \(info)"
            completion(header)
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
    
    // 날씨 정보가 이미 표시된 (날짜 + 공항 쌍) 키를 추적
    var displayedWeatherKeys: Set<String> = []
    
    // CLOSE 버튼 – 모달로 팝업될 때만 보이도록 함
    let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("CLOSE", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        // 버튼 배경은 흰색, 텍스트는 "Ocean" 색상으로 설정
        button.backgroundColor = .white
        button.setTitleColor(UIColor(named: "Ocean"), for: .normal)
        button.layer.cornerRadius = 8
        return button
    }()
    
    // viewDidLoad 내에서 TODAY 버튼을 항상 내비게이션 바 오른쪽에 추가
    override func viewDidLoad() {
        super.viewDidLoad()
        self.modalPresentationStyle = .automatic

        // 타이틀 설정 (선택된 날짜가 있으면 함께 표시)
        if selectedDate.isEmpty {
            self.title = "Detail Schedule Info"
        } else {
            self.title = "Detail Schedule Info (\(selectedDate))"
        }
        
        view.backgroundColor = .white
        setupTableView()
        setupCloseButton()
        
        // TODAY 버튼 구성 (iOS 17 이상) - Filled 스타일 사용
        let todayButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()        // Filled 스타일의 버튼 구성 사용
        config.title = " TODAY "                              // 버튼 제목 (앞뒤 공백 포함)
        config.baseBackgroundColor = UIColor(named: "LightRed")// 배경색: LightRed (Assets에 등록된 색상)
        config.baseForegroundColor = UIColor(named: "LightWhite")// 글씨 색상: LightWhite (Assets에 등록된 색상)
        config.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3) // 내부 여백 설정
        todayButton.configuration = config                    // 구성 적용
        todayButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold) // 글씨 폰트 설정
        todayButton.configuration?.cornerStyle = .capsule     // 캡슐 형태로 모서리 둥글게 처리
        
        // 버튼 액션 연결
        todayButton.addTarget(self, action: #selector(scrollToToday), for: .touchUpInside)
        // 내비게이션 바 오른쪽에 커스텀 버튼 추가
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: todayButton)
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 모달로 프레젠트된 경우에만 CLOSE 버튼과 네비게이션 바 스타일 적용
        if self.presentingViewController != nil {
            closeButton.isHidden = false
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.navigationBar.barTintColor = UIColor(named: "Ocean")
            navigationController?.navigationBar.isTranslucent = false
            navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        } else {
            // 모달이 아니라면 CLOSE 버튼은 숨김
            closeButton.isHidden = true
        }
        
        displayedWeatherKeys.removeAll()
        sortScheduleDetails()
        tableView.reloadData()
        prefetchWeatherData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 뷰가 완전히 나타난 후 오늘(혹은 가장 가까운) 스케줄로 자동 스크롤
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let indexPath = self.indexForTodayOrNearest() {
                // .top 옵션을 사용하여 셀이 화면 최상단에 위치하도록 스크롤
                self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.layoutIfNeeded()
        var additionalHeight: CGFloat = 20
        // 아이패드에서는 CLOSE 버튼 높이만큼 추가하여 창이 줄어들지 않도록 함
        if UIDevice.current.userInterfaceIdiom == .pad {
            additionalHeight += closeButton.frame.height + 10
        }
        self.preferredContentSize = CGSize(width: self.view.frame.width,
                                           height: tableView.contentSize.height + additionalHeight)
    }
    
    // MARK: - CLOSE 버튼 설정 및 액션
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
    
    // MARK: - TableView Setup
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
            // 테이블 뷰의 상단은 CLOSE 버튼 아래쪽에서 시작하도록 offset 적용
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - 새로고침 액션
    @objc func refreshData(_ sender: UIRefreshControl) {
        WeatherDataCache.shared.clearCache()
        displayedWeatherKeys.removeAll()
        prefetchWeatherData()
        sortScheduleDetails()
        tableView.reloadData()
        sender.endRefreshing()
    }
    
    // MARK: - 데이터 정렬
    func sortScheduleDetails() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        scheduleDetailsList.sort { dict1, dict2 in
            let dateString1 = dict1["DepDate"] ?? selectedDate
            let dateString2 = dict2["DepDate"] ?? selectedDate
            if let date1 = dateFormatter.date(from: dateString1),
               let date2 = dateFormatter.date(from: dateString2) {
                return date1 < date2
            }
            return dateString1 < dateString2
        }
    }
    
    // MARK: - 날씨 데이터 미리 가져오기
    func prefetchWeatherData() {
        var airportCodes = Set<String>()
        for schedule in scheduleDetailsList {
            if let workType = schedule["WorkType"], (workType == "FLY" || workType == "TVL") {
                if let depAp = schedule["DepAp"], !depAp.isEmpty {
                    airportCodes.insert(depAp)
                }
                if let arrAp = schedule["ArrAp"], !arrAp.isEmpty {
                    airportCodes.insert(arrAp)
                }
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
    
    // MARK: - AWC API를 사용한 METAR 데이터 호출 (IATA → ICAO 변환 후 요청)
    // METAR 결과는 오직 원문(raw_text)만 사용합니다.
    func fetchMETAR(for airportCode: String, completion: @escaping (String?) -> Void) {
        guard let icao = convertIATAToICAO(airportCode) else {
            print("IATA to ICAO 변환 실패: \(airportCode)")
            completion(nil)
            return
        }
        if let cached = WeatherDataCache.shared.getMETAR(for: icao) {
            completion(cached)
            return
        }
        let urlString = "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=xml&taf=false"
        guard let url = URL(string: urlString) else { completion(nil); return }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("METAR 요청 오류: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else { completion(nil); return }
            let parserDelegate = AWCXMLParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = parserDelegate
            if parser.parse(), let metarText = parserDelegate.foundText {
                let finalMetarText = metarText
                WeatherDataCache.shared.setMETAR(finalMetarText, for: icao)
                completion(finalMetarText)
            } else {
                print("METAR XML 파싱 실패")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - AWC API를 사용한 TAF 데이터 호출 (IATA → ICAO 변환 후 요청)
    func fetchTAF(for airportCode: String, completion: @escaping (String?) -> Void) {
        guard let icao = convertIATAToICAO(airportCode) else {
            print("IATA to ICAO 변환 실패: \(airportCode)")
            completion(nil)
            return
        }
        if let cached = WeatherDataCache.shared.getTAF(for: icao) {
            completion(cached)
            return
        }
        let urlString = "https://aviationweather.gov/api/data/taf?ids=\(icao)&format=xml&metar=false&time=valid"
        guard let url = URL(string: urlString) else { completion(nil); return }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("TAF 요청 오류: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else { completion(nil); return }
            let parserDelegate = AWCXMLParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = parserDelegate
            if parser.parse(), var tafText = parserDelegate.foundText {
                let tokens = ["BECMG", "FM", "TEMPO", "PROB", "NOSIG"]
                for token in tokens {
                    tafText = tafText.replacingOccurrences(of: " \(token)", with: "\n\(token)")
                }
                WeatherDataCache.shared.setTAF(tafText, for: icao)
                completion(tafText)
            } else {
                print("TAF XML 파싱 실패")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - 비행 관련 추가 날씨 정보 가져오기 (공항 헤더 정보 포함)
    // 출력 형식:
    // [출발공항] flight_category & 공항정보
    // METAR: (출발 METAR 원문)
    // TAF: (출발 TAF)
    // [도착공항] flight_category & 공항정보
    // METAR: (도착 METAR 원문)
    // TAF: (도착 TAF)
    func fetchFlightAdditionalInfo(for schedule: [String: String], indexPath: IndexPath, currentText: NSAttributedString) {
        guard let depAp = schedule["DepAp"], let arrAp = schedule["ArrAp"] else { return }
        
        let dateKey = schedule["DepDate"] ?? selectedDate
        let sortedAirports = [depAp, arrAp].sorted()
        let weatherKey = "\(dateKey)_\(sortedAirports[0])_\(sortedAirports[1])"
        // 이미 날씨 정보가 표시되었으면 리턴
        if displayedWeatherKeys.contains(weatherKey) {
            return
        }
        displayedWeatherKeys.insert(weatherKey)
        
        let dispatchGroup = DispatchGroup()
        var depMetarStr: String?
        var depTafStr: String?
        var arrMetarStr: String?
        var arrTafStr: String?
        
        dispatchGroup.enter()
        fetchMETAR(for: depAp) { metar in
            depMetarStr = metar
            dispatchGroup.leave()
        }
        dispatchGroup.enter()
        fetchTAF(for: depAp) { taf in
            depTafStr = taf
            dispatchGroup.leave()
        }
        dispatchGroup.enter()
        fetchMETAR(for: arrAp) { metar in
            arrMetarStr = metar
            dispatchGroup.leave()
        }
        dispatchGroup.enter()
        fetchTAF(for: arrAp) { taf in
            arrTafStr = taf
            dispatchGroup.leave()
        }
        
        let headerGroup = DispatchGroup()
        var depHeader: String = "[\(depAp)] N/A"
        var arrHeader: String = "[\(arrAp)] N/A"
        
        headerGroup.enter()
        fetchHeaderInfo(for: depAp) { header in
            depHeader = header
            headerGroup.leave()
        }
        headerGroup.enter()
        fetchHeaderInfo(for: arrAp) { header in
            arrHeader = header
            headerGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            headerGroup.notify(queue: .main) {
                let additionalText = """
                
                --- FLT WX INFO ---
                \(depHeader)
                METAR: \(depMetarStr ?? "N/A")
                TAF: \(depTafStr ?? "N/A")
                --- FLT WX INFO ---
                \(arrHeader)
                METAR: \(arrMetarStr ?? "N/A")
                TAF: \(arrTafStr ?? "N/A")
                """
                let additionalAttr = NSAttributedString(string: additionalText, attributes: [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.systemGreen
                ])
                if let cell = self.tableView.cellForRow(at: indexPath) {
                    let combined = NSMutableAttributedString(attributedString: currentText)
                    combined.append(additionalAttr)
                    cell.textLabel?.attributedText = combined
                    
                    self.tableView.beginUpdates()
                    self.tableView.endUpdates()
                    self.preferredContentSize = CGSize(width: self.view.frame.width,
                                                       height: self.tableView.contentSize.height + 20)
                }
            }
        }
    }
    
    // MARK: - UITableViewDataSource Methods
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scheduleDetailsList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let details = scheduleDetailsList[indexPath.row]
        
        // 날짜 포매터 설정
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd"
        
        let depDateOriginal = details["DepDate"] ?? selectedDate
        let arrDateOriginal = details["ArrDate"] ?? selectedDate
        
        let depDateFormatted = inputFormatter.date(from: depDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? depDateOriginal
        let arrDateFormatted = inputFormatter.date(from: arrDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? arrDateOriginal
        
        // 오늘 스케줄 여부 판단 (DepDate 기준)
        let isToday: Bool = {
            if let depDateStr = details["DepDate"],
               let scheduleDate = inputFormatter.date(from: depDateStr) {
                return Calendar.current.isDate(scheduleDate, inSameDayAs: Date())
            }
            return false
        }()
        
        // 오늘 스케줄이면 기본 폰트 크기를 1.5배로 사용
        let defaultFont = isToday ? UIFont.systemFont(ofSize: 14 * 1.5) : UIFont.systemFont(ofSize: 14)
        let boldFont = isToday ? UIFont.boldSystemFont(ofSize: 20 * 1.5) : UIFont.boldSystemFont(ofSize: 20)
        // 오늘 스케줄이면 텍스트 색상을 LightDark로 사용, 아니라면 기본 색상 (여기서는 label 색상)
        let textColor: UIColor = isToday ? (UIColor(named: "LightDark") ?? .black) : UIColor.label
        
        // 셀 배경색: 오늘 스케줄이면 LightYellow, 아니면 기본값 (clear)
        cell.backgroundColor = isToday ? UIColor(named: "LightYellow") : .clear
        
        let workType = details["WorkType"] ?? "N/A"
        
        let attributedText = NSMutableAttributedString()
        
        if workType == "FLY" || workType == "TVL" {
            var item = details["Item"] ?? "N/A"
            let depAp = details["DepAp"] ?? "N/A"
            let depTimeLocal = details["DepStnTime"] ?? "N/A"
            let arrAp = details["ArrAp"] ?? "N/A"
            let arrTimeLocal = details["ArrStnTime"] ?? "N/A"
            let flyingHours = details["FlyingHours"] ?? "N/A"
            let dutyHours = details["DutyHours"] ?? "N/A"
            
            var transportIcon = ""
            if workType == "FLY" {
                transportIcon = "✈️"
            } else if workType == "TVL" {
                transportIcon = "📌"
                if !item.isEmpty {
                    item = "DH" + item.dropFirst(2)
                }
            }
            
            let dateLine: String
            if depDateFormatted == arrDateFormatted {
                dateLine = "📅 \(depDateFormatted)"
            } else {
                dateLine = "📅 \(depDateFormatted) ~ \(arrDateFormatted)"
            }
            attributedText.append(NSAttributedString(string: dateLine, attributes: [
                .font: defaultFont,
                .foregroundColor: textColor
            ]))
            
            let departureStr = "\(depTimeLocal) \(depAp)"
            let arrivalStr = "\(arrTimeLocal) \(arrAp)"
            
            let flightLine = "\n\(transportIcon) "
            attributedText.append(NSAttributedString(string: flightLine, attributes: [
                .font: defaultFont,
                .foregroundColor: textColor
            ]))
            attributedText.append(NSAttributedString(string: item, attributes: [
                .font: boldFont,
                .foregroundColor: textColor
            ]))
            
            var detailsLine = "\n📍 \(departureStr) - \(arrivalStr)\n⏳ FLT TIME: \(flyingHours)\n⌛ DUTY HOURS: \(dutyHours)"
            if let hotel = details["Hotel"], !hotel.isEmpty {
                detailsLine += "\n🏨 Hotel: \(hotel)"
            }
            attributedText.append(NSAttributedString(string: detailsLine, attributes: [
                .font: defaultFont,
                .foregroundColor: textColor
            ]))
            
            // 동일한 날짜에 동일한 공항 쌍인 경우, 그룹 내 마지막 스케줄에서만 추가 날씨 정보를 표시
            let dateKey = details["DepDate"] ?? selectedDate
            let currentGroup = Set([depAp.uppercased(), arrAp.uppercased()])
            
            if let firstIndexForGroup = scheduleDetailsList.firstIndex(where: { schedule in
                guard let scheduleDate = schedule["DepDate"],
                      let groupDep = schedule["DepAp"],
                      let groupArr = schedule["ArrAp"] else { return false }
                return scheduleDate == dateKey && Set([groupDep.uppercased(), groupArr.uppercased()]) == currentGroup
            }),
               let lastIndexForGroup = scheduleDetailsList.lastIndex(where: { schedule in
                guard let scheduleDate = schedule["DepDate"],
                      let groupDep = schedule["DepAp"],
                      let groupArr = schedule["ArrAp"] else { return false }
                return scheduleDate == dateKey && Set([groupDep.uppercased(), groupArr.uppercased()]) == currentGroup
            }) {
                if lastIndexForGroup == indexPath.row {
                    let firstSchedule = scheduleDetailsList[firstIndexForGroup]
                    let displayDepAp = firstSchedule["DepAp"] ?? depAp
                    let displayArrAp = firstSchedule["ArrAp"] ?? arrAp
                    
                    var modifiedDetails = details
                    modifiedDetails["DepAp"] = displayDepAp
                    modifiedDetails["ArrAp"] = displayArrAp
                    
                    fetchFlightAdditionalInfo(for: modifiedDetails, indexPath: indexPath, currentText: attributedText)
                }
            }
            
        } else {
            let activity = details["Activity"] ?? "N/A"
            let dutyReport = details["DutyReport"] ?? "N/A"
            let dutyDebrief = details["DutyDebrief"] ?? "N/A"
            
            var pureDutyDebrief = dutyDebrief
            if let parenIndex = dutyDebrief.firstIndex(of: "(") {
                pureDutyDebrief = String(dutyDebrief[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if let dutyDebriefDateStr = details["DutyDebriefDate"],
               dutyDebriefDateStr != (details["DepDate"] ?? "") {
                let dutyDebriefFormatted = inputFormatter.date(from: dutyDebriefDateStr).flatMap { outputFormatter.string(from: $0) } ?? dutyDebriefDateStr
                attributedText.append(NSAttributedString(string: "📅 \(depDateFormatted) ~ \(dutyDebriefFormatted)\n", attributes: [
                    .font: defaultFont,
                    .foregroundColor: textColor
                ]))
            } else {
                attributedText.append(NSAttributedString(string: "📅 \(depDateFormatted)\n", attributes: [
                    .font: defaultFont,
                    .foregroundColor: textColor
                ]))
            }
            
            let icon = (activity == "DO") ? "🏠" : "🏢"
            let activityPrefix = "\(icon) "
            attributedText.append(NSAttributedString(string: activityPrefix, attributes: [
                .font: defaultFont,
                .foregroundColor: textColor
            ]))
            attributedText.append(NSAttributedString(string: activity, attributes: [
                .font: boldFont,
                .foregroundColor: textColor
            ]))
            attributedText.append(NSAttributedString(string: " : \(dutyReport) - \(pureDutyDebrief)", attributes: [
                .font: defaultFont,
                .foregroundColor: textColor
            ]))
        }
        
        cell.textLabel?.attributedText = attributedText
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        return cell
    }

    
    // MARK: - UITableViewDelegate Methods
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let schedule = scheduleDetailsList[indexPath.row]
        let editVC = ScheduleEditViewController()
        editVC.schedule = schedule
        editVC.scheduleIndex = indexPath.row
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "삭제") { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            self.scheduleDetailsList.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            self.updateGlobalSchedulesFromDetails()
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    // MARK: - ScheduleEditDelegate Methods
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int) {
        scheduleDetailsList[index] = schedule
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        updateGlobalSchedulesFromDetails()
    }
    
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int) {
        scheduleDetailsList.remove(at: index)
        tableView.reloadData()
        updateGlobalSchedulesFromDetails()
    }
    
    // MARK: - 글로벌 스케줄 업데이트 (UserDefaults)
    func updateGlobalSchedulesFromDetails() {
        guard !selectedDate.isEmpty else { return }
        
        var globalSchedules: [String: [[String: String]]] = [:]
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                globalSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            } catch {
                print("글로벌 스케줄 로드 실패: \(error)")
            }
        }
        
        var updatedGroup: [String: [[String: String]]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        for schedule in scheduleDetailsList {
            if let depDate = schedule["DepDate"] {
                updatedGroup[depDate, default: []].append(schedule)
            }
        }
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        let selectedMonth = selectedDate
        
        for key in globalSchedules.keys {
            if let date = dateFormatter.date(from: key) {
                let keyMonth = monthFormatter.string(from: date)
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
            if let date = dateFormatter.date(from: key) {
                let keyMonth = monthFormatter.string(from: date)
                if keyMonth == selectedMonth {
                    globalSchedules[key] = value
                }
            }
        }
        
        do {
            let data = try JSONEncoder().encode(globalSchedules)
            UserDefaults.standard.set(data, forKey: schedulesUserDefaultsKey)
            print("글로벌 스케줄 저장 성공")
        } catch {
            print("글로벌 스케줄 저장 실패: \(error)")
        }
    }
    
    // MARK: - (Optional) 왼쪽 설명 레이블 생성 함수
    func createLeftLabel(text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        label.textColor = .darkGray
        label.sizeToFit()
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: label.frame.width + 10, height: label.frame.height))
        label.frame.origin = CGPoint(x: 5, y: (containerView.frame.height - label.frame.height) / 2)
        containerView.addSubview(label)
        return containerView
    }
    
    // MARK: - 콘솔에 스케줄 출력 함수
    func printSchedulesToConsole() {
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey),
           let globalSchedules = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
            print("----- 저장된 스케줄 출력 -----")
            for (date, entries) in globalSchedules {
                print("날짜: \(date)")
                for entry in entries {
                    print("스케줄: \(entry)")
                }
            }
            print("----- 출력 완료 -----")
        } else {
            print("글로벌 스케줄 데이터가 없습니다.")
        }
    }
    
    // MARK: - 오늘(또는 가장 가까운) 스케줄 인덱스 찾기
    /// 스케줄 리스트를 순회하여 오늘 날짜와 동일한 스케줄이 있다면 해당 인덱스를 반환합니다.
    /// 만약 오늘 날짜 스케줄이 없다면, 오늘 이후의 첫 번째 스케줄을 반환하고,
    /// 모든 스케줄이 오늘 이전인 경우 마지막 스케줄의 인덱스를 반환합니다.
    func indexForTodayOrNearest() -> IndexPath? {
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var nearestIndex: Int?
        for (index, schedule) in scheduleDetailsList.enumerated() {
            if let dateString = schedule["DepDate"],
               let scheduleDate = dateFormatter.date(from: dateString) {
                // 오늘 날짜와 동일한 경우 바로 반환
                if Calendar.current.isDate(scheduleDate, inSameDayAs: today) {
                    return IndexPath(row: index, section: 0)
                }
                // 오늘 이후인 첫 스케줄을 후보로 지정
                if scheduleDate > today, nearestIndex == nil {
                    nearestIndex = index
                }
            }
        }
        if let index = nearestIndex {
            return IndexPath(row: index, section: 0)
        }
        // 모든 스케줄이 오늘 이전인 경우 마지막 스케줄 인덱스 반환
        if !scheduleDetailsList.isEmpty {
            return IndexPath(row: scheduleDetailsList.count - 1, section: 0)
        }
        return nil
    }
    
    // MARK: - TODAY 버튼 액션 (내비게이션 바 버튼)
    @objc func scrollToToday() {
        if let indexPath = indexForTodayOrNearest() {
            // .top 옵션을 사용하여 셀이 화면 최상단에 위치하도록 스크롤
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        } else {
            // 오늘의 스케줄 및 가까운 스케줄이 없는 경우 알림 표시
            let alert = UIAlertController(title: "ALERT", message: "There are no scheduled events for today or later.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}
