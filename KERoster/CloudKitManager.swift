//
//  CloudKitManager.swift
//  KERoster
//
//  Created by 윤정섭 on 10/24/25.
//

import Foundation
import CloudKit

// CloudKit에 올릴 전체 스냅샷
struct CloudState: Codable {
    var schedules: [String: [[String: String]]]
    var ownerInfo: String
    var totalHoursByMonth: [String: String]
    var updatedAt: Date
}

final class CloudKitManager {
    static let shared = CloudKitManager()

    private let container: CKContainer
    private let database: CKDatabase

    // 사용자별 싱글톤 레코드
    private let recordID = CKRecord.ID(recordName: "KERosterUserData")
    private let recordType = "UserData"

    // 사일런트 푸시용 구독 ID
    private let dbSubscriptionID = "KERosterDBSub"

    /// 컨테이너를 지정하고 싶으면 identifier를 넘겨서 생성 (예: "iCloud.org.duckdns.cageyjs.KERoster")
    init(containerID: String? = nil) {
        if let id = containerID {
            self.container = CKContainer(identifier: id)
        } else {
            self.container = CKContainer.default()
        }
        self.database = container.privateCloudDatabase
    }

    // MARK: - Subscription (사일런트 푸시)
    /// 앱 시작 시 한 번 호출: 기존에 있으면 유지, 없으면 생성
    func subscribeIfNeeded() {
        database.fetch(withSubscriptionID: dbSubscriptionID) { [weak self] existing, error in
            guard let self = self else { return }
            if let existing = existing {
                #if DEBUG
                print("✅ CloudKit subscription already exists: \(existing.subscriptionID)")
                #endif
                return
            }
            if let error = error as? CKError, error.code != .unknownItem {
                // unknownItem이면 "구독 없음"이므로 무시
                print("❌ fetch subscription error: \(error)")
            }

            let sub = CKDatabaseSubscription(subscriptionID: self.dbSubscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true // 🔈 사일런트 푸시
            sub.notificationInfo = info

            self.database.save(sub) { _, err in
                if let err = err {
                    print("❌ CloudKit subscribe failed: \(err)")
                } else {
                    print("✅ CloudKit subscribed (DB-wide)")
                }
            }
        }
    }

    // MARK: - Fetch (Pull)
    /// 서버에 저장된 스냅샷을 가져옴. 없으면 .success(nil)
    func fetch(completion: @escaping (Result<CloudState?, Error>) -> Void) {
        database.fetch(withRecordID: recordID) { record, error in
            if let ckErr = error as? CKError, ckErr.code == .unknownItem {
                completion(.success(nil)) // 아직 저장 없음
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
                // CKAsset 우선(대용량 대비), 없으면 Data 필드도 허용
                if let asset = record["payload"] as? CKAsset,
                   let url = asset.fileURL {
                    let data = try Data(contentsOf: url)
                    let state = try JSONDecoder().decode(CloudState.self, from: data)
                    completion(.success(state))
                } else if let data = record["payload"] as? Data {
                    let state = try JSONDecoder().decode(CloudState.self, from: data)
                    completion(.success(state))
                } else {
                    completion(.success(nil))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Save (Push / Upsert)
    /// 스냅샷을 저장(있으면 업데이트, 없으면 생성)
    func save(state: CloudState, completion: @escaping (Result<Void, Error>) -> Void) {
        database.fetch(withRecordID: recordID) { [weak self] existing, _ in
            guard let self = self else { return }
            let record = existing ?? CKRecord(recordType: self.recordType, recordID: self.recordID)

            do {
                let data = try JSONEncoder().encode(state)

                // Asset로 저장(안정적 & 용량 여유)
                let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("keroster_payload.json")
                // 기존 파일 제거 후 기록
                try? FileManager.default.removeItem(at: tmpURL)
                try data.write(to: tmpURL, options: .atomic)

                record["payload"] = CKAsset(fileURL: tmpURL)
                record["updatedAt"] = state.updatedAt as NSDate

                let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                op.savePolicy = .changedKeys

                if #available(iOS 15.0, *) {
                    op.modifyRecordsResultBlock = { result in
                        try? FileManager.default.removeItem(at: tmpURL)
                        switch result {
                        case .success:
                            completion(.success(()))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    // iOS 14 이하 호환
                    op.modifyRecordsCompletionBlock = { _, _, error in
                        try? FileManager.default.removeItem(at: tmpURL)
                        if let error = error { completion(.failure(error)) }
                        else { completion(.success(())) }
                    }
                }

                self.database.add(op)
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - 편의 별칭
    func pull(_ completion: @escaping (Result<CloudState?, Error>) -> Void) { fetch(completion: completion) }
    func push(_ state: CloudState, completion: @escaping (Result<Void, Error>) -> Void) { save(state: state, completion: completion) }
}
