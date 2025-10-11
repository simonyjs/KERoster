//
//  CrewListFlightDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 10/11/25.
//

import UIKit

final class CrewListFlightDetailViewController: UIViewController, UITableViewDataSource {

    var entry: [String: String] = [:]

    private var crew: [[String: String]] = []
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        title = (entry["Item"] ?? "Flight")
        if let json = entry["CrewList"],
           let data = json.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: String]] {
            crew = arr
        }

        tableView.dataSource = self
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { crew.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = crew[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let name = c["Name"] ?? "(No Name)"
        let role = c["Role"] ?? ""
        cell.textLabel?.text = name + (role.isEmpty ? "" : "  (\(role))")

        var subs: [String] = []
        if let rank = c["PostingRank"], !rank.isEmpty { subs.append("Rank: \(rank)") }
        if let work = c["WorkType"], !work.isEmpty { subs.append("Type: \(work)") }
        if let id = c["CrewID"], !id.isEmpty { subs.append("ID: \(id)") }
        if let code = c["PICCode"], !code.isEmpty { subs.append("Code: \(code)") }
        if let sdc = c["SDC"], !sdc.isEmpty { subs.append("SDC: \(sdc)") }
        if let contact = c["Contact"], !contact.isEmpty { subs.append("Contact: \(contact)") }
        cell.detailTextLabel?.text = subs.joined(separator: " • ")
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }
}

