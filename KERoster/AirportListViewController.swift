//
//  AirportListViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 11/21/25.
//

import UIKit

class AirportListViewController: UITableViewController {
    
    // ViewController 에서 넘겨받는 전체 스케줄
    var schedules: [String: [[String:String]]] = [:]
    
    // 공항코드 → 그 공항을 포함하는 레그들 (WT = FLY/TVL 만)
    private var airportIndex: [String: [AirportFlightRef]] = [:]
    
    // 섹션 제목 (A, B, C …)
    private var sectionTitles: [String] = []
    // 섹션별 공항코드 리스트
    private var airportsInSection: [String: [String]] = [:]
    
    // 공항코드 → 공항 이름 (ApList.json에서 로드)
    private var airportNameByCode: [String: String] = [:]
    // 공항코드 → ICAO 코드 (ApList.json에서 로드)
    private var airportICAOByCode: [String: String] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Airport Summary"
        tableView.rowHeight = 60
        tableView.separatorStyle = .singleLine
        
        loadAirportNames()
        buildAirportIndex()
    }
    
    /// ApList.json 에서 IATA → 이름 / ICAO 매핑 생성
    private func loadAirportNames() {
        guard let path = Bundle.main.path(forResource: "ApList", ofType: "json") else {
            print("❌ ApList.json path not found in main bundle")
            return
        }
        print("✅ ApList.json path = \(path)")
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            print("✅ ApList.json data size = \(data.count) bytes")
            
            guard let arr = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                print("❌ ApList.json is not [[String: Any]] array")
                return
            }
            print("✅ ApList.json array count = \(arr.count)")
            
            if let first = arr.first {
                print("🔍 First airport row keys = \(Array(first.keys))")
            }
            
            var nameMap: [String: String] = [:]
            var icaoMap: [String: String] = [:]
            
            for obj in arr {
                // IATA 코드
                guard let code = obj["IATA"] as? String,
                      !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                
                // 이름
                let rawName = (obj["name"] as? String) ?? ""
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    nameMap[code] = name
                }
                
                // ICAO
                let rawICAO = (obj["ICAO"] as? String) ?? ""
                let icao = rawICAO.trimmingCharacters(in: .whitespacesAndNewlines)
                if !icao.isEmpty {
                    icaoMap[code] = icao
                }
            }
            
            airportNameByCode = nameMap
            airportICAOByCode = icaoMap
            print("✅ Loaded airportNameByCode count = \(airportNameByCode.count)")
            print("✅ Loaded airportICAOByCode count = \(airportICAOByCode.count)")
            
        } catch {
            print("❌ ApList.json load error: \(error)")
        }
    }

    
    /// schedules 를 공항/알파벳 섹션별로 인덱싱 (WT = FLY/TVL 만 포함)
    private func buildAirportIndex() {
        var tmp: [String: [AirportFlightRef]] = [:]
        
        for (dateKey, entries) in schedules {
            for (idx, entry) in entries.enumerated() {
                let wt = (entry["WorkType"] ?? "").uppercased()
                // ✈️ FLY / TVL 만 대상
                guard wt == "FLY" || wt == "TVL" else { continue }
                
                let ref = AirportFlightRef(dateKey: dateKey, indexInDay: idx, entry: entry)
                
                let dep = (entry["DepAp"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let arr = (entry["ArrAp"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !dep.isEmpty {
                    tmp[dep, default: []].append(ref)
                }
                if !arr.isEmpty, arr != dep {
                    tmp[arr, default: []].append(ref)
                }
            }
        }
        
        airportIndex = tmp
        
        // 공항코드들을 알파벳 섹션(A/B/C…)으로 나누기
        var secMap: [String: [String]] = [:]
        for code in tmp.keys {
            guard let first = code.first else { continue }
            let sec = String(first) // "A", "B", ...
            secMap[sec, default: []].append(code)
        }
        
        // 섹션 제목 정렬 + 섹션 내 공항코드 정렬
        var sections: [String] = []
        var airportsPerSection: [String: [String]] = [:]
        for (sec, codes) in secMap {
            sections.append(sec)
            airportsPerSection[sec] = codes.sorted()
        }
        
        sectionTitles = sections.sorted()
        airportsInSection = airportsPerSection
        
        tableView.reloadData()
    }
    
    // MARK: - TableView DataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sectionTitles.count
    }
    
    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        let sec = sectionTitles[section]
        return airportsInSection[sec]?.count ?? 0
    }
    
    // 섹션 헤더: A / B / C … (음영 배경)
    override func tableView(_ tableView: UITableView,
                            viewForHeaderInSection section: Int) -> UIView? {
        let title = sectionTitles[section]
        
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        
        let label = UILabel()
        label.text = "  \(title)"     // 왼쪽 여백 조금
        label.font = .boldSystemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }
    
    override func tableView(_ tableView: UITableView,
                            heightForHeaderInSection section: Int) -> CGFloat {
        return 28
    }
    
    // 오른쪽 알파벳 인덱스
    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return sectionTitles
    }
    
    override func tableView(_ tableView: UITableView,
                            sectionForSectionIndexTitle title: String,
                            at index: Int) -> Int {
        return sectionTitles.firstIndex(of: title) ?? 0
    }
    
    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 🔹 두 줄짜리 셀 (1줄: IATA [ICAO] - N Flight(s), 2줄: 공항 이름)
        let cellId = "AirportCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellId)
        
        let sec = sectionTitles[indexPath.section]
        guard let codes = airportsInSection[sec], indexPath.row < codes.count else {
            return cell
        }
        let code = codes[indexPath.row]               // IATA
        let flights = airportIndex[code] ?? []
        let name = airportNameByCode[code] ?? ""
        let icao = airportICAOByCode[code] ?? ""
        
        // 첫 줄: 예) "GMP [RKSS] - 10 Flight(s)"
        if !icao.isEmpty {
            cell.textLabel?.text = "\(code) [\(icao)] - \(flights.count) Flight(s)"
        } else {
            cell.textLabel?.text = "\(code) - \(flights.count) Flight(s)"
        }
        cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        cell.textLabel?.numberOfLines = 1
        
        // 둘째 줄: 공항 이름만
        cell.detailTextLabel?.text = name
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 13)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 1
        
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    // MARK: - TableView Delegate
    
    override func tableView(_ tableView: UITableView,
                            didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let sec = sectionTitles[indexPath.section]
        guard let codes = airportsInSection[sec], indexPath.row < codes.count else { return }
        let code = codes[indexPath.row]
        guard let flights = airportIndex[code] else { return }
        
        // 날짜 기준 최신 순으로 정렬 (이미 FLY/TVL만 있음)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "dd-MMM-yyyy"
        
        let sortedFlights = flights.sorted { lhs, rhs in
            let ldStr = lhs.entry["DepDate"] ?? lhs.entry["Date"] ?? lhs.dateKey
            let rdStr = rhs.entry["DepDate"] ?? rhs.entry["Date"] ?? rhs.dateKey
            let ld = df.date(from: ldStr) ?? Date.distantPast
            let rd = df.date(from: rdStr) ?? Date.distantPast
            if ld != rd { return ld > rd } // 최근날짜 우선
            let lt = lhs.entry["DepStnTime"] ?? lhs.entry["DutyReport"] ?? ""
            let rt = rhs.entry["DepStnTime"] ?? rhs.entry["DutyReport"] ?? ""
            return lt > rt
        }
        
        let sb = UIStoryboard(name: "Main", bundle: nil)
        if let vc = sb.instantiateViewController(withIdentifier: "AirportFlightListViewController") as? AirportFlightListViewController {
            vc.airportCode = code
            vc.airportName = airportNameByCode[code]
            vc.flights = sortedFlights
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}
