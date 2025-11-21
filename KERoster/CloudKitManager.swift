//
//  CloudKitManager.swift
//  KERoster
//
//  Created by 윤정섭 on 10/24/25.
//

import Foundation
import CloudKit

// ======================================================
// MARK: - Cloud Payload Model
// ======================================================

struct CloudState: Codable {
    var schedules: [String: [[String: String]]]
    var ownerInfo: String
    var totalHoursByMonth: [String: String]
    var updatedAt: Date
}

// ======================================================
// MARK: - CloudKit Manager (Improved Version)
// ======================================================

final class CloudKitManager {

    static let shared = CloudKitManager()

    private let container: CKContainer
    private let database: CKDatabase

    private let recordID = CKRecord.ID(recordName: "KERosterUserData")
    private let recordType = "UserData"

    private let subscriptionID = "KERosterDBSub"

    /// 만약 특정 컨테이너 사용시 containerID 전달
    init(containerID: String? = nil) {
        if let id = containerID {
            container = CKContainer(identifier: id)
        } else {
            container = CKContainer.default()
        }
        database = container.privateCloudDatabase
    }

    // ======================================================
    // MARK: - 1) Silent Push Subscription
    // ======================================================

    func subscribeIfNeeded() {
        database.fetch(withSubscriptionID: subscriptionID) { [weak self] existing, error in
            guard let self else { return }

            if existing != nil {
                print("✔ CloudKit: Subscription already exists")
                return
            }

            if let ckErr = error as? CKError, ckErr.code != .unknownItem {
                print("❌ subscription fetch error: \(ckErr)")
            }

            let sub = CKDatabaseSubscription(subscriptionID: subscriptionID)

            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true  // silent push
            sub.notificationInfo = info

            self.database.save(sub) { _, err in
                if let err = err {
                    print("❌ CloudKit subscription failed: \(err)")
                } else {
                    print("✔ CloudKit: Subscription created")
                }
            }
        }
    }

    // ======================================================
    // MARK: - 2) Fetch (Pull)
    // ======================================================

    func fetch(completion: @escaping (Result<CloudState?, Error>) -> Void) {
        database.fetch(withRecordID: recordID) { record, error in

            if let ckErr = error as? CKError, ckErr.code == .unknownItem {
                completion(.success(nil))
                return
            }
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let record = record else {
                completion(.success(nil))
                return
            }

            do {
                // 1) CKAsset 우선
                if let asset = record["payload"] as? CKAsset,
                   let url = asset.fileURL {

                    let data = try Data(contentsOf: url)
                    let state = try JSONDecoder().decode(CloudState.self, from: data)
                    completion(.success(state))
                    return
                }

                // 2) Data 필드 fallback
                if let data = record["payload"] as? Data {
                    let state = try JSONDecoder().decode(CloudState.self, from: data)
                    completion(.success(state))
                    return
                }

                completion(.success(nil))

            } catch {
                completion(.failure(error))
            }
        }
    }

    // ======================================================
    // MARK: - 3) Save (Push)
    // ======================================================

    func save(state: CloudState, completion: @escaping (Result<Void, Error>) -> Void) {

        database.fetch(withRecordID: recordID) { [weak self] existing, _ in
            guard let self else { return }

            let record = existing ?? CKRecord(recordType: self.recordType,
                                              recordID: self.recordID)

            do {
                let data = try JSONEncoder().encode(state)

                // Asset 저장
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("keroster_payload.json")

                try? FileManager.default.removeItem(at: tempURL)
                try data.write(to: tempURL)

                record["payload"] = CKAsset(fileURL: tempURL)
                record["updatedAt"] = state.updatedAt as NSDate

                let op = CKModifyRecordsOperation(recordsToSave: [record],
                                                  recordIDsToDelete: nil)

                op.savePolicy = .allKeys  // 충돌 방지

                op.modifyRecordsResultBlock = { result in
                    try? FileManager.default.removeItem(at: tempURL)

                    switch result {
                    case .success:
                        print("✔ CloudKit push OK")
                        completion(.success(()))
                    case .failure(let err):
                        print("❌ push error: \(err)")
                        completion(.failure(err))
                    }
                }

                self.database.add(op)

            } catch {
                completion(.failure(error))
            }
        }
    }

    // ======================================================
    // MARK: - 4) Convenience Alias
    // ======================================================

    func pull(_ completion: @escaping (Result<CloudState?, Error>) -> Void) {
        fetch(completion: completion)
    }

    func push(_ state: CloudState, completion: @escaping (Result<Void, Error>) -> Void) {
        save(state: state, completion: completion)
    }

    // ======================================================
    // MARK: - 5) FORCE SYNC FEATURE (신규)
    // ======================================================

    /// 앱 활성화/포그라운드 시 호출하면 동기화 100% 보장됨
    func forceSync(completion: (() -> Void)? = nil) {
        pull { result in
            NotificationCenter.default.post(name: .cloudKitUpdated, object: nil)
            completion?()
        }
    }
}
