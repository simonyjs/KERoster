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
//

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
        var people: [Person]
    }

    // 인덱스(표시/탐색용)
    private var refsByPerson: [Person: [FlightRef]] = [:]
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

    // FLY/TVL 판정
    private let flightWT: Set<String> = ["FLY","TVL"]
    private func normWT(_ entry: [String:String]) -> String {
        (entry["WorkType"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    private func isFlightEntry(_ entry: [String:String]) -> Bool {
        flightWT.contains(normWT(entry))
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Crew by Person"

        view.backgroundColor = KERosterPalette.tableBackground
        tableView.backgroundColor = KERosterPalette.tableBackground
        tableView.separatorStyle = .none

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.contentInset = .zero
        tableView.scrollIndicatorInsets = .zero

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

        buildPeopleIndex()      // WT 상관없이 CrewList 기준으로 사람 인덱싱

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        tableView.sectionIndexColor = KERosterPalette.sectionIndex
        tableView.sectionIndexBackgroundColor = .clear
        if #available(iOS 13.0, *) {
            tableView.sectionIndexTrackingBackgroundColor = KERosterPalette.sectionIndexTracking
        }

        if sections.isEmpty {
            let lbl = UILabel()
            lbl.text = "NO CREW LIST ON SKD!"
            lbl.textAlignment = .center
            lbl.textColor = KERosterPalette.emptyLabel
            lbl.numberOfLines = 0
            tableView.backgroundView = lbl
        } else {
            tableView.backgroundView = nil
        }
    }

    // MARK: - Build Index (사람별 + 동일 ID 병합 + 섹션 인덱스)
    private func buildPeopleIndex() {
        refsByPerson.removeAll()

        struct Accum { var name: String; var id: String; var refs: [FlightRef] }
        var bucket: [String: Accum] = [:]

        for (dateKey, entries) in schedules {
            for e in entries {
                // WT 필터 없음. CrewList가 있는 스케줄은 모두 인덱싱 대상.
                guard let json = e["CrewList"],
                      let data = json.data(using: .utf8),
                      let crewArr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]],
                      !crewArr.isEmpty else { continue }

                for c in crewArr {
                    guard let nameRaw = firstValue(in: c, keys: Self.nameKeys),
                          !nameRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                    let idRaw = firstValue(in: c, keys: Self.idKeys) ?? "—"

                    let name = nameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = idRaw.trimmingCharacters(in: .whitespacesAndNewlines)

                    // 여기(문자열 보간)에서 에러가 나기 쉬워서, 정규화 문자열을 분리해서 안전하게 처리
                    let key: String = {
                        if !id.isEmpty && id != "—" {
                            return "id:\(id.lowercased())"
                        } else {
                            let normalizedName = name
                                .replacingOccurrences(of: " ", with: "")
                                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                            return "name:\(normalizedName)"
                        }
                    }()

                    var acc = bucket[key] ?? Accum(name: name, id: id, refs: [])
                    acc.name = betterName(pref: acc.name, cand: name)
                    if acc.id == "—", id != "—" { acc.id = id }

                    acc.refs.append(FlightRef(dateKey: dateKey, entry: e))
                    bucket[key] = acc
                }
            }
        }

        var allPeople: [Person] = []
        for (_, acc) in bucket {
            let person = Person(name: acc.name, id: acc.id)
            refsByPerson[person] = acc.refs
            allPeople.append(person)
        }

        var sectionDict: [String: [Person]] = [:]
        for p in allPeople {
            let sk = indexKey(for: p.name)
            sectionDict[sk, default: []].append(p)
        }

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

        sectionIndexMap.removeAll()
        for (i, s) in sections.enumerated() { sectionIndexMap[s.key] = i }
    }

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
            if let alt = dict.first(where: {
                $0.key.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(
                    k.replacingOccurrences(of: " ", with: "")
                ) == .orderedSame
            })?.value,
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
        if up.range(of: "^[A-Z]$", options: .regularExpression) != nil { return up }
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

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].key
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let v = UIView()
        v.backgroundColor = KERosterPalette.headerBackground

        let label = UILabel()
        label.text = "  \(sections[section].key)"
        label.font = UIFont.boldSystemFont(ofSize: 14)
        label.textColor = KERosterPalette.primary
        label.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: v.topAnchor),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])

        let hairline = UIView()
        hairline.backgroundColor = KERosterPalette.headerHairline
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

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 28 }

    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return sections.map { $0.key }
    }

    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return sectionIndexMap[title] ?? index
    }

    // 셀 간 3pt 간격(커스텀 spacer)
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.contentView.subviews.filter { $0.tag == 1001 }.forEach { $0.removeFromSuperview() }

        let spacer = UIView(frame: CGRect(x: 0,
                                          y: cell.contentView.bounds.height - 3,
                                          width: cell.contentView.bounds.width,
                                          height: 3))
        spacer.backgroundColor = tableView.backgroundColor ?? KERosterPalette.tableBackground
        spacer.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        spacer.tag = 1001
        cell.contentView.addSubview(spacer)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let p = sections[indexPath.section].people[indexPath.row]
        let refs = refsByPerson[p] ?? []

        // flight / other count 분리
        let flightCount = refs.reduce(0) { $0 + (isFlightEntry($1.entry) ? 1 : 0) }
        let otherCount  = refs.count - flightCount

        let countText: String = {
            if otherCount > 0 {
                return "\(flightCount) flight(s) • \(otherCount) other(s)"
            } else {
                return "\(flightCount) flight(s)"
            }
        }()

        let title = p.name
        let subtitle = (p.id == "—")
            ? countText
            : "[\(p.id)]  •  \(countText)"

        let bold = UIFont.boldSystemFont(ofSize: 18)
        let reg  = UIFont.systemFont(ofSize: 14)

        let att = NSMutableAttributedString(
            string: title + "\n",
            attributes: [.font: bold, .foregroundColor: KERosterPalette.textPrimary]
        )
        att.append(NSAttributedString(
            string: subtitle,
            attributes: [.font: reg, .foregroundColor: KERosterPalette.textSecondary]
        ))

        // 기존 왼쪽 bar 제거
        cell.contentView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }

        // 왼쪽 Bar
        let bar = UIView(frame: CGRect(x: 3, y: 0, width: 5, height: cell.contentView.bounds.height))
        bar.backgroundColor = KERosterPalette.primary
        bar.autoresizingMask = [.flexibleHeight]
        bar.tag = 999
        cell.contentView.addSubview(bar)

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = att
        cell.backgroundColor = KERosterPalette.primaryBackground
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let person = sections[indexPath.section].people[indexPath.row]
        guard let refs = refsByPerson[person] else { return }

        let sb = UIStoryboard(name: "Main", bundle: nil)
        if let vc = sb.instantiateViewController(withIdentifier: "PersonFlightsViewController") as? PersonFlightsViewController {
            vc.person = PersonFlightsViewController.Person(name: person.name, id: person.id)
            vc.flights = refs.map { .init(dateKey: $0.dateKey, entry: $0.entry) } // Flight + Other 모두 전달
            vc.inputFmt = inputFmt
            _ = vc.view
            if vc.tableView == nil {
                let ac = UIAlertController(
                    title: "Outlet 미연결",
                    message: "PersonFlightsViewController의 tableView 아웃렛을 연결하세요.",
                    preferredStyle: .alert
                )
                ac.addAction(UIAlertAction(title: "확인", style: .default))
                present(ac, animated: true)
                return
            }
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}
