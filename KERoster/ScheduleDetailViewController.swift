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

// MARK: - AVWX API 응답 모델
struct AirportInfo: Decodable {
    let name: String
    let city: String
    let country: String
    let iata: String
    let icao: String
    // 필요 시 추가 필드 선언
}

struct METAR: Decodable {
    let raw: String
}

struct TAF: Decodable {
    let raw: String
}

// MARK: - 응답 캐싱 (TTL 1시간 적용)
class WeatherDataCache {
    static let shared = WeatherDataCache()
    private init() { }
    
    // TTL: 1시간 = 3600초
    private let ttl: TimeInterval = 3600
    
    // 캐시 항목과 저장 시각을 함께 저장
    private var airportInfoCache: [String: (data: AirportInfo, date: Date)] = [:]
    private var metarCache: [String: (data: String, date: Date)] = [:]
    private var tafCache: [String: (data: String, date: Date)] = [:]
    
    func getAirportInfo(for key: String) -> AirportInfo? {
        if let entry = airportInfoCache[key], Date().timeIntervalSince(entry.date) < ttl {
            return entry.data
        }
        return nil
    }
    
    func setAirportInfo(_ info: AirportInfo, for key: String) {
        airportInfoCache[key] = (info, Date())
    }
    
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
        airportInfoCache.removeAll()
        metarCache.removeAll()
        tafCache.removeAll()
    }
}

class ScheduleDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, ScheduleEditDelegate {
    
    // MARK: - Properties
    var scheduleDetailsList: [[String: String]] = []
    var selectedDate: String = ""
    
    let tableView = UITableView()
    let schedulesUserDefaultsKey = "schedules"
    
    // MARK: - View LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // 모달 프레젠테이션 스타일을 .automatic 으로 설정
        self.modalPresentationStyle = .automatic
        
        if selectedDate.isEmpty {
            self.title = "Schedule Details"
        } else {
            self.title = "Schedule Details (\(selectedDate))"
        }
        
        view.backgroundColor = .white
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sortScheduleDetails()
        tableView.reloadData()
        // 프리페칭: 스케줄 내 모든 비행 관련 공항 코드의 데이터를 미리 가져옴
        prefetchWeatherData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.layoutIfNeeded()
        self.preferredContentSize = CGSize(width: self.view.frame.width, height: tableView.contentSize.height + 20)
    }
    
    // MARK: - TableView Setup
    func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView() // 빈 셀 제거
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc func refreshData(_ sender: UIRefreshControl) {
        // 수동 새로고침 시 캐시 초기화 후 프리페칭
        WeatherDataCache.shared.clearCache()
        prefetchWeatherData()
        sortScheduleDetails()
        tableView.reloadData()
        sender.endRefreshing()
    }
    
    // MARK: - Data Sorting
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
    
    // MARK: - Pre-fetching Weather Data
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
            if WeatherDataCache.shared.getAirportInfo(for: code) == nil {
                fetchAirportInfo(for: code) { _ in }
            }
            if WeatherDataCache.shared.getMETAR(for: code) == nil {
                fetchMETAR(for: code) { _ in }
            }
            if WeatherDataCache.shared.getTAF(for: code) == nil {
                fetchTAF(for: code) { _ in }
            }
        }
    }
    
    // MARK: - AVWX API 호출 함수들 (캐싱 적용)
    func fetchAirportInfo(for airportCode: String, completion: @escaping (AirportInfo?) -> Void) {
        if let cached = WeatherDataCache.shared.getAirportInfo(for: airportCode) {
            completion(cached)
            return
        }
        let urlString = "https://avwx.rest/api/station/\(airportCode)?format=json"
        guard let url = URL(string: urlString) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.addValue("U62wY39v-wjG_tb0NuT6k6Joo3sniCBH7-uJxB3o7W0", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("공항 API 요청 오류: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else { completion(nil); return }
            do {
                let info = try JSONDecoder().decode(AirportInfo.self, from: data)
                WeatherDataCache.shared.setAirportInfo(info, for: airportCode)
                completion(info)
            } catch {
                print("공항 API JSON 디코딩 오류: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }
    
    func fetchMETAR(for airportCode: String, completion: @escaping (String?) -> Void) {
        if let cached = WeatherDataCache.shared.getMETAR(for: airportCode) {
            completion(cached)
            return
        }
        let urlString = "https://avwx.rest/api/metar/\(airportCode)?format=json&options=info,translate"
        guard let url = URL(string: urlString) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.addValue("U62wY39v-wjG_tb0NuT6k6Joo3sniCBH7-uJxB3o7W0", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("METAR 요청 오류: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else { completion(nil); return }
            do {
                let metar = try JSONDecoder().decode(METAR.self, from: data)
                WeatherDataCache.shared.setMETAR(metar.raw, for: airportCode)
                completion(metar.raw)
            } catch {
                print("METAR JSON 디코딩 오류: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }
    
    func fetchTAF(for airportCode: String, completion: @escaping (String?) -> Void) {
        if let cached = WeatherDataCache.shared.getTAF(for: airportCode) {
            completion(cached)
            return
        }
        let urlString = "https://avwx.rest/api/taf/\(airportCode)?format=json&options=info,translate"
        guard let url = URL(string: urlString) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.addValue("U62wY39v-wjG_tb0NuT6k6Joo3sniCBH7-uJxB3o7W0", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("TAF 요청 오류: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else { completion(nil); return }
            do {
                let taf = try JSONDecoder().decode(TAF.self, from: data)
                WeatherDataCache.shared.setTAF(taf.raw, for: airportCode)
                completion(taf.raw)
            } catch {
                print("TAF JSON 디코딩 오류: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - 비행 관련 추가 정보 가져오기 (출발/도착 공항 정보, METAR, TAF)
    func fetchFlightAdditionalInfo(for schedule: [String: String], indexPath: IndexPath, currentText: NSAttributedString) {
        guard let depAp = schedule["DepAp"], let arrAp = schedule["ArrAp"] else { return }
        let dispatchGroup = DispatchGroup()
        
        var depAirportInfoStr: String?
        var depMetarStr: String?
        var depTafStr: String?
        var arrAirportInfoStr: String?
        var arrMetarStr: String?
        var arrTafStr: String?
        
        dispatchGroup.enter()
        fetchAirportInfo(for: depAp) { info in
            if let info = info {
                depAirportInfoStr = "\(info.name) (\(info.iata)) - \(info.city), \(info.country)"
            }
            dispatchGroup.leave()
        }
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
        fetchAirportInfo(for: arrAp) { info in
            if let info = info {
                arrAirportInfoStr = "\(info.name) (\(info.iata)) - \(info.city), \(info.country)"
            }
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
        
        dispatchGroup.notify(queue: .main) {
            let additionalText = """
            
            --- FLT WX INFO ---
            [DEP]
            A/P: \(depAirportInfoStr ?? "N/A")
            METAR: \(depMetarStr ?? "N/A")
            TAF: \(depTafStr ?? "N/A")
            [ARR]
            A/P: \(arrAirportInfoStr ?? "N/A")
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
                
                // 강제로 테이블 뷰 레이아웃 업데이트하고 모달의 preferredContentSize 재설정
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
                self.preferredContentSize = CGSize(width: self.view.frame.width,
                                                   height: self.tableView.contentSize.height + 20)
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
        
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd-MMM-yyyy"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd"
        
        let depDateOriginal = details["DepDate"] ?? selectedDate
        let arrDateOriginal = details["ArrDate"] ?? selectedDate
        
        let depDateFormatted = inputFormatter.date(from: depDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? depDateOriginal
        let arrDateFormatted = inputFormatter.date(from: arrDateOriginal).flatMap { outputFormatter.string(from: $0) } ?? arrDateOriginal
        
        let workType = details["WorkType"] ?? "N/A"
        
        let defaultFont = UIFont.systemFont(ofSize: 14)
        let boldFont = UIFont.boldSystemFont(ofSize: 20)
        
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
            attributedText.append(NSAttributedString(string: dateLine, attributes: [.font: defaultFont]))
            
            let departureStr = "\(depTimeLocal) \(depAp)"
            let arrivalStr = "\(arrTimeLocal) \(arrAp)"
            
            let flightLine = "\n\(transportIcon) "
            attributedText.append(NSAttributedString(string: flightLine, attributes: [.font: defaultFont]))
            attributedText.append(NSAttributedString(string: item, attributes: [.font: boldFont]))
            
            var detailsLine = "\n📍 \(departureStr) - \(arrivalStr)\n⏳ FLT TIME: \(flyingHours)\n⌛ DUTY HOURS: \(dutyHours)"
            if let hotel = details["Hotel"], !hotel.isEmpty {
                detailsLine += "\n🏨 Hotel: \(hotel)"
            }
            attributedText.append(NSAttributedString(string: detailsLine, attributes: [.font: defaultFont]))
            
            fetchFlightAdditionalInfo(for: details, indexPath: indexPath, currentText: attributedText)
            
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
                attributedText.append(NSAttributedString(string: "📅 \(depDateFormatted) ~ \(dutyDebriefFormatted)\n", attributes: [.font: defaultFont]))
            } else {
                attributedText.append(NSAttributedString(string: "📅 \(depDateFormatted)\n", attributes: [.font: defaultFont]))
            }
            
            let icon = (activity == "DO") ? "🏠" : "🏢"
            let activityPrefix = "\(icon) "
            attributedText.append(NSAttributedString(string: activityPrefix, attributes: [.font: defaultFont]))
            attributedText.append(NSAttributedString(string: activity, attributes: [.font: boldFont]))
            attributedText.append(NSAttributedString(string: " : \(dutyReport) - \(pureDutyDebrief)", attributes: [.font: defaultFont]))
        }
        
        cell.textLabel?.attributedText = attributedText
        cell.textLabel?.numberOfLines = 0
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
}
