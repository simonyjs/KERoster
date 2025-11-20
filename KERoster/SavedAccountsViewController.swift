//
//  SavedAccountsViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 11/20/25.
//
//  저장된 iFlight 계정 목록 화면

import UIKit

final class SavedAccountsViewController: UITableViewController {

    private var accounts: [String] = []

    // LoginViewController에서 선택 결과를 받기 위한 클로저
    var onSelectAccount: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Saved iFlight IDs"

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        // 오른쪽 상단 Edit 버튼 (스와이프 삭제)
        navigationItem.rightBarButtonItem = editButtonItem

        reloadAccounts()
    }

    private func reloadAccounts() {
        accounts = KeychainService.allAccounts()
        tableView.reloadData()
    }

    // MARK: - TableView DataSource

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        return accounts.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let account = accounts[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = account
        cell.contentConfiguration = config
        return cell
    }

    // MARK: - Row 선택 (ID 선택해서 되돌려주기)

    override func tableView(_ tableView: UITableView,
                            didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let account = accounts[indexPath.row]
        onSelectAccount?(account)   // 호출자에게 콜백
        navigationController?.popViewController(animated: true)
    }

    // MARK: - 삭제 (스와이프 Delete)

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        let account = accounts[indexPath.row]
        if KeychainService.deletePassword(account: account) {
            accounts.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        } else {
            // 실패한 경우 간단한 알럿
            let alert = UIAlertController(title: "Delete Failed",
                                          message: "Could not delete this account from Keychain.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
