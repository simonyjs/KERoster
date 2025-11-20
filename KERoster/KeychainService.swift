//
//  KeychainService.swift
//  KERoster
//
//  Created by 윤정섭 on 11/20/25.
//
//  iFlight용 ID/비밀번호 관리

import Foundation
import Security

struct KeychainService {
    // service 이름은 앱 번들에 맞춰서 원하는 걸로 써도 됨
    private static let service = "org.duckdns.cageyjs.KERoster.iFlight"
    private static let accountsKey = "iFlightAccounts"   // 저장된 account 리스트용

    // MARK: - Save (덮어쓰기)
    @discardableResult
    static func savePassword(_ password: String, account: String) -> Bool {
        guard !account.isEmpty,
              let data = password.data(using: .utf8) else { return false }

        // 1) 기존 동일 account 삭제
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 2) 새로 추가
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            addAccountToList(account)
            return true
        } else {
            print("Keychain save error: \(status)")
            return false
        }
    }

    // MARK: - Load
    static func loadPassword(account: String) -> String? {
        guard !account.isEmpty else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    // MARK: - Delete (완전 삭제)
    @discardableResult
    static func deletePassword(account: String) -> Bool {
        guard !account.isEmpty else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            removeAccountFromList(account)
            return true
        } else {
            print("Keychain delete error: \(status)")
            return false
        }
    }

    // MARK: - 계정 리스트 (UI용)
    static func allAccounts() -> [String] {
        // 필요하면 App Group UserDefaults로 바꿔도 됨
        let defaults = UserDefaults.standard
        let arr = defaults.stringArray(forKey: accountsKey) ?? []
        // 중복 제거 + 정렬
        return Array(Set(arr)).sorted()
    }

    // MARK: - 내부: UserDefaults에 account 목록 유지
    private static func addAccountToList(_ account: String) {
        guard !account.isEmpty else { return }
        let defaults = UserDefaults.standard
        var arr = defaults.stringArray(forKey: accountsKey) ?? []
        if !arr.contains(account) {
            arr.append(account)
            defaults.set(arr, forKey: accountsKey)
        }
    }

    private static func removeAccountFromList(_ account: String) {
        guard !account.isEmpty else { return }
        let defaults = UserDefaults.standard
        var arr = defaults.stringArray(forKey: accountsKey) ?? []
        if let idx = arr.firstIndex(of: account) {
            arr.remove(at: idx)
            defaults.set(arr, forKey: accountsKey)
        }
    }
}
