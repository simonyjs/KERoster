//
//  AppDelegate.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/22.
//

import UIKit
import Foundation
import CoreData
import CloudKit

// 화면 쪽에서 pull 트리거 받을 알림
// (프로젝트 내 중복 선언 주의)
extension Notification.Name {
    static let cloudKitUpdated = Notification.Name("CloudKitUpdated")
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // ✅ KVS 동기화/옵저버 전량 제거 (CloudKit로 대체)
        // NSUbiquitousKeyValueStore.default.synchronize()  // 삭제
        // didChangeExternallyNotification 옵저버           // 삭제

        // ✅ CloudKit DB 변경 → 사일런트 푸시 구독(최초 1회 생성)
        CloudKitManager.shared.subscribeIfNeeded()

        // ✅ 원격 푸시 등록 (Background Modes → Remote notifications 체크 필수)
        application.registerForRemoteNotifications()

        // (선택) CloudKit 계정 상태 로깅
        CKContainer.default().accountStatus { status, error in
            #if DEBUG
            if let error = error { print("iCloud account status error: \(error)") }
            else { print("iCloud account status: \(status.rawValue)") }
            #endif
        }

        return true
    }

    // MARK: - Remote Notifications (silent push from CloudKit)

    // APNs 등록 성공/실패(선택) – 사일런트 푸시에 꼭 필요하진 않지만 디버그에 유용
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        print("✅ Registered for remote notifications. token length=\(deviceToken.count)")
        #endif
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }

    // CloudKit DB 구독 푸시 수신 → 화면 쪽 동기화 트리거
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        // CloudKit 푸시 파싱
        let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)

        // CloudKitManager.subscribeIfNeeded()에서 사용한 구독 ID와 동일해야 함
        if ckNotification?.subscriptionID == "KERosterDBSub" {
            // 앱 어느 화면에서든 이 알림을 받아 pull() 호출하도록 처리
            NotificationCenter.default.post(name: .cloudKitUpdated, object: nil)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration",
                                    sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    // MARK: - Core Data stack (미사용이면 전부 삭제 가능)

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "KERoster")
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        return container
    }()

    // MARK: - Core Data Saving support
    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do { try context.save() }
            catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}
