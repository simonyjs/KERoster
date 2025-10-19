//
//  CrewListByMonthViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 10/11/25.
//
//  사람별 목록(이름→아이디 정렬) + 동일 ID(대소문자 무시) 병합
//  오른쪽 섹션 인덱스: A~Z + #
//  섹션 헤더(A/B/C 줄) 음영 처리
//  이름 탭 시 그 사람의 비행 리스트 화면으로 push

import UIKit

final class CrewListByMonthViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    @IBOutlet weak var tableView: UITableView!   // 스토리보드 연결 필수!

    // 외부에서 전달 가능 (비어 있으면 iCloud/AppGroup에서 로드)
    var schedules: [String: [[String: String]]] = [:]

    // MARK: - Models
    struct Person: Hashable {
        let name: String
        let id: String
    }
    struct FlightRef {
        let dateKey: String   // "dd-MMM-yyyy"
        let entry: [String: String]
    }
    struct Section {
        let key: String               // 섹션 키(예: A, B, #)
        var people: [Person]          // 섹션 내 사람 목록
    }

    // 인덱스(표시/탐색용)
    private var flightsByPerson: [Person: [FlightRef]] = [:]
    private var sections: [Section] = []
    private var sectionIndexMap: [String: Int] = [:]  // 인덱스 문자열 → 섹션 번호

    // MARK: - DateFormatters
    private let inputFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy"
        return f
    }()

    // A~Z 고정 배열
    private let latinOrder = (65...90).compactMap { String(UnicodeScalar($0)) } // "A"..."Z"

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Crew by Person"
        view.backgroundColor = .systemBackground

        // 데이터 로드
        if schedules.isEmpty {
            NSUbiquitousKeyValueStore.default.synchronize()
            if let json = NSUbiquitousKeyValueStore.default.string(forKey: "schedules_json"),
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
                schedules = decoded
            } else if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
                      let data = shared.data(forKey: "schedules"),
                      let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
                schedules = decoded
            }
        }

        buildPeopleIndex()      // 동일 ID 병합 + 섹션/인덱스 구성

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        // 인덱스 바 톤 조절
        tableView.sectionIndexColor = .secondaryLabel
        tableView.sectionIndexBackgroundColor = .clear
        if #available(iOS 13.0, *) {
            tableView.sectionIndexTrackingBackgroundColor = .tertiarySystemBackground
        }

        if sections.isEmpty {
            let lbl = UILabel()
            lbl.text = "NO CREW LIST ON SKD!"
            lbl.textAlignment = .center
            lbl.textColor = .secondaryLabel
            lbl.numberOfLines = 0
            tableView.backgroundView = lbl
        } else {
            tableView.backgroundView = nil
        }
    }

    // MARK: - Build Index (사람별 + 동일 ID 병합 + 섹션 인덱스)
    private func buildPeopleIndex() {
        flightsByPerson.removeAll()

        // 1) 동일인 병합: 기본 키 = ID(대소문자 무시), ID 없으면 이름(대소문자/공백 무시)
        struct Accum { var name: String; var id: String; var flights: [FlightRef] }
        var bucket: [String: Accum] = [:]

        let workFilter: Set<String> = ["FLY", "TVL"]

        for (dateKey, entries) in schedules {
            for e in entries {
                let wt = (e["WorkType"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !workFilter.contains(wt) { continue }

                guard let json = e["CrewList"],
                      let data = json.data(using: .utf8),
                      let crewArr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]],
                      !crewArr.isEmpty else { continue }

                for c in crewArr {
                    guard let nameRaw = firstValue(in: c, keys: Self.nameKeys),
                          !nameRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                    let idRaw = firstValue(in: c, keys: Self.idKeys) ?? "—"

                    // 정규화
                    let name = nameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = idRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key: String = {
                        if !id.isEmpty && id != "—" {
                            return "id:\(id.lowercased())"    // ✅ ID 대소문자 무시 병합
                        } else {
                            // ID 없으면 이름으로 병합(공백 제거 + case folding)
                            return "name:\(name.replacingOccurrences(of: " ", with: "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))"
                        }
                    }()

                    var acc = bucket[key] ?? Accum(name: name, id: id, flights: [])
                    // 이름이 다르게 들어오는 경우, 더 "보기 좋은" 이름을 채택
                    acc.name = betterName(pref: acc.name, cand: name)
                    // ID는 실제 값이 있는 쪽 우선
                    if acc.id == "—", id != "—" { acc.id = id }

                    acc.flights.append(FlightRef(dateKey: dateKey, entry: e))
                    bucket[key] = acc
                }
            }
        }

        // 2) flightsByPerson 채우기 + 정렬 준비
        var allPeople: [Person] = []
        for (_, acc) in bucket {
            let person = Person(name: acc.name, id: acc.id)
            flightsByPerson[person] = acc.flights
            allPeople.append(person)
        }

        // 3) 섹션 키 생성(A~Z / 기타는 #)
        var sectionDict: [String: [Person]] = [:]
        for p in allPeople {
            let sk = indexKey(for: p.name)
            sectionDict[sk, default: []].append(p)
        }

        // 4) 섹션 순서 정리 + 섹션 내 정렬(이름→아이디)
        let orderKeys = orderedIndexKeys(from: Array(sectionDict.keys))
        sections = orderKeys.map { key in
            var arr = sectionDict[key] ?? []
            arr.sort {
                let r = $0.name.localizedStandardCompare($1.name)
                if r == .orderedSame {
                    return $0.id.localizedStandardCompare($1.id) == .orderedAscending
                }
                return r == .orderedAscending
            }
            return Section(key: key, people: arr)
        }

        // 5) 인덱스 맵
        sectionIndexMap.removeAll()
        for (i, s) in sections.enumerated() { sectionIndexMap[s.key] = i }
    }

    // 이름 후보 중 더 보기 좋은 표시형 선택
    private func betterName(pref: String, cand: String) -> String {
        func score(_ s: String) -> Int {
            var sc = 0
            if s == s.capitalized { sc += 2 }
            if s.contains(" ") { sc += 1 }
            if s.count > pref.count { sc += 1 }
            return sc
        }
        return score(cand) > score(pref) ? cand : pref
    }

    // 파싱에 사용할 키 후보들 (대소문자/스페이스 혼재 대비)
    private static let nameKeys: [String] = [
        "Name","CrewName","CREW_NAME","CREW NAME","FullName","FULL_NAME","Crew","crewname","name"
    ]
    private static let idKeys: [String] = [
        "ID","CrewID","Crew Id","Crew_Id","CrewNo","Crew No","EmpID","EMPID","EmpNo","EMP_NO","EmployeeID","EmployeeNo","id","crewId","empNo"
    ]

    private func firstValue(in dict: [String:String], keys: [String]) -> String? {
        for k in keys {
            if let v = dict[k], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 키 정규화(공백/대소문자)
            if let alt = dict.first(where: { $0.key.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(k.replacingOccurrences(of: " ", with: "")) == .orderedSame })?.value,
               !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return alt.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // MARK: - 섹션 인덱스 계산 (A~Z + #)
    private func indexKey(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = trimmed.first else { return "#" }
        let up = String(c).uppercased()
        // 라틴 알파벳 한 글자면 그 알파벳, 아니면 #
        if up.range(of: "^[A-Z]$", options: .regularExpression) != nil {
            return up
        }
        return "#"
    }

    private func orderedIndexKeys(from keys: [String]) -> [String] {
        var ordered: [String] = []
        for k in latinOrder where keys.contains(k) { ordered.append(k) }
        if keys.contains("#") { ordered.append("#") }
        return ordered
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].people.count
    }

    // 기본 타이틀(VoiceOver 등 접근성 보조)
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].key
    }

    // 커스텀 헤더(음영 처리)
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground

        let label = UILabel()
        label.text = "  \(sections[section].key)" // 좌측 약간 들여쓰기
        label.font = UIFont.boldSystemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: v.topAnchor),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])

        // 아래 헤어라인
        let hairline = UIView()
        hairline.backgroundColor = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
            hairline.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])

        return v
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 28
    }

    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        // 오른쪽 인덱스 바에 표시
        return sections.map { $0.key }
    }

    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        // 인덱스 탭 → 섹션 번호
        return sectionIndexMap[title] ?? index
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let p = sections[indexPath.section].people[indexPath.row]
        let flights = flightsByPerson[p] ?? []

        let title = "\(p.name)"
        let subtitle = p.id == "—" ? "\(flights.count) flight(s)" : "[\(p.id)]  •  \(flights.count) flight(s)"

        let bold = UIFont.boldSystemFont(ofSize: 18)
        let reg  = UIFont.systemFont(ofSize: 14)

        let att = NSMutableAttributedString(string: title + "\n", attributes: [.font: bold])
        att.append(NSAttributedString(string: subtitle, attributes: [.font: reg]))

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = att
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let person = sections[indexPath.section].people[indexPath.row]
        guard let flights = flightsByPerson[person] else { return }

        let sb = UIStoryboard(name: "Main", bundle: nil)
        if let vc = sb.instantiateViewController(withIdentifier: "PersonFlightsViewController") as? PersonFlightsViewController {
            vc.person = PersonFlightsViewController.Person(name: person.name, id: person.id)
            vc.flights = flights.map { .init(dateKey: $0.dateKey, entry: $0.entry) }
            vc.inputFmt = inputFmt
            // 아웃렛 확인(미연결 방지)
            _ = vc.view
            if vc.tableView == nil {
                let ac = UIAlertController(title: "Outlet 미연결", message: "PersonFlightsViewController의 tableView 아웃렛을 연결하세요.", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "확인", style: .default))
                present(ac, animated: true)
                return
            }
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}
