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
import BackgroundTasks   // BGTask 사용

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Info.plist의 BGTaskSchedulerPermittedIdentifiers와 반드시 동일해야 함
    private let refreshTaskID    = "org.duckdns.cageyjs.KERoster.refresh"
    private let processingTaskID = "org.duckdns.cageyjs.KERoster.processing"

    // MARK: - App Launch

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        #if DEBUG
        print("[AppDelegate] didFinishLaunching started")
        #endif

        // CloudKit DB 변경 → 사일런트 푸시 구독(최초 1회 생성)
        CloudKitManager.shared.subscribeIfNeeded()
        #if DEBUG
        print("[AppDelegate] CloudKit subscription requested (subscribeIfNeeded)")
        #endif

        // 원격 푸시 등록 (Background Modes → Remote notifications 체크 필수)
        application.registerForRemoteNotifications()
        #if DEBUG
        print("[AppDelegate] registerForRemoteNotifications() called")
        #endif

        // (선택) CloudKit 계정 상태 로깅
        CKContainer.default().accountStatus { status, error in
            #if DEBUG
            if let error = error {
                print("[AppDelegate] iCloud account status error: \(error)")
            } else {
                print("[AppDelegate] iCloud account status: \(status.rawValue)")
            }
            #endif
        }

        // BGTask 핸들러 등록 (앱/백그라운드 런치 모두 대비)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            #if DEBUG
            print("[AppDelegate] BGAppRefreshTask fired")
            #endif
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskID, using: nil) { task in
            #if DEBUG
            print("[AppDelegate] BGProcessingTask fired")
            #endif
            self.handleProcessing(task: task as! BGProcessingTask)
        }

        #if DEBUG
        print("[AppDelegate] BGTask handlers registered")
        print("[AppDelegate] didFinishLaunching completed")
        #endif

        return true
    }

    // MARK: - App → Background

    func applicationDidEnterBackground(_ application: UIApplication) {
        #if DEBUG
        print("[AppDelegate] applicationDidEnterBackground")
        #endif

        // 백그라운드 진입 시 다음 기회 스케줄
        scheduleAppRefresh()
        scheduleProcessing()
    }

    // MARK: - Remote Notifications (silent push from CloudKit)

    // APNs 등록 성공 – 사일런트 푸시에 꼭 필요하진 않지만 디버그에 유용
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        let tokenHex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[AppDelegate] Registered for remote notifications. token length = \(deviceToken.count)")
        print("[AppDelegate] APNs device token (hex): \(tokenHex)")
        #endif
    }

    // APNs 등록 실패
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
    }

    // CloudKit DB 구독 푸시 수신 → 화면 쪽 동기화 트리거
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        #if DEBUG
        print("[AppDelegate] didReceiveRemoteNotification called")
        if let aps = userInfo["aps"] {
            print("[AppDelegate] userInfo[\"aps\"] = \(aps)")
        }
        #endif

        let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)

        #if DEBUG
        if let subscriptionID = ckNotification?.subscriptionID {
            print("[AppDelegate] CKNotification subscriptionID = \(subscriptionID)")
        } else {
            print("[AppDelegate] CKNotification has no subscriptionID")
        }
        #endif

        // 우리가 등록한 CloudKit DB Subscription이 아닐 경우 무시
        guard ckNotification?.subscriptionID == "KERosterDBSub" else {
            #if DEBUG
            print("[AppDelegate] Remote notification is not for KERosterDBSub. Ignoring.")
            #endif
            completionHandler(.noData)
            return
        }

        #if DEBUG
        print("[AppDelegate] CloudKit DB change notification received. Start pull()")
        #endif

        // CloudKit에서 최신 상태 받아서 로컬 저장소에 반영
        CloudKitManager.shared.pull { result in
            switch result {
            case .success(let state):
                guard let state = state else {
                    print("[AppDelegate] CloudKit pull success but state is nil")
                    completionHandler(.noData)
                    return
                }

                // App Group UserDefaults에 schedules 저장
                if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster") {
                    if let data = try? JSONEncoder().encode(state.schedules) {
                        sharedDefaults.set(data, forKey: "schedules")
                        #if DEBUG
                        print("[AppDelegate] Schedules saved to App Group UserDefaults")
                        #endif
                    } else {
                        #if DEBUG
                        print("[AppDelegate] Failed to encode schedules for App Group")
                        #endif
                    }
                } else {
                    #if DEBUG
                    print("[AppDelegate] Failed to get App Group UserDefaults")
                    #endif
                }

                // 일반 UserDefaults에 ownerInfo / totalHoursByMonth 저장
                UserDefaults.standard.set(state.ownerInfo, forKey: "ownerInfo")
                UserDefaults.standard.set(state.totalHoursByMonth, forKey: "totalHoursByMonth")
                UserDefaults.standard.synchronize()
                #if DEBUG
                print("[AppDelegate] ownerInfo & totalHoursByMonth saved to UserDefaults")
                #endif

                // 화면에게 "로컬 데이터 바뀌었다" 알림
                NotificationCenter.default.post(name: .cloudKitUpdated, object: nil)
                #if DEBUG
                print("[AppDelegate] Notification .cloudKitUpdated posted")
                #endif

                // (선택) BG 작업 재예약
                self.scheduleAppRefresh()
                self.scheduleProcessing()

                completionHandler(.newData)

            case .failure(let error):
                print("[AppDelegate] CloudKit pull error in didReceiveRemoteNotification: \(error)")
                completionHandler(.failed)
            }
        }
    }

    // MARK: - Legacy Background Fetch (옵션)

    func application(_ application: UIApplication,
                     performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // 가벼운 동기화/타임라인 갱신 등
        #if DEBUG
        print("[AppDelegate] performFetchWithCompletionHandler called → posting .cloudKitUpdated")
        #endif

        NotificationCenter.default.post(name: .cloudKitUpdated, object: nil)
        completionHandler(.newData)
    }

    // MARK: - BGTask: Schedule

    private func scheduleAppRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15분 후 earliest

        do {
            try BGTaskScheduler.shared.submit(req)
            #if DEBUG
            print("[AppDelegate] BGAppRefresh scheduled (earliest in 15 minutes)")
            #endif
        } catch {
            #if DEBUG
            print("[AppDelegate] BGAppRefresh submit error: \(error)")
            #endif
        }
    }

    private func scheduleProcessing() {
        let req = BGProcessingTaskRequest(identifier: processingTaskID)
        req.requiresNetworkConnectivity = true    // 네트워크 필요시
        req.requiresExternalPower = false         // 전원 연결 필요시 true

        do {
            try BGTaskScheduler.shared.submit(req)
            #if DEBUG
            print("[AppDelegate] BGProcessing scheduled")
            #endif
        } catch {
            #if DEBUG
            print("[AppDelegate] BGProcessing submit error: \(error)")
            #endif
        }
    }

    // MARK: - BGTask: Handlers

    private func handleAppRefresh(task: BGAppRefreshTask) {
        #if DEBUG
        print("[AppDelegate] handleAppRefresh started")
        #endif

        // 다음 기회 재스케줄
        scheduleAppRefresh()

        let queue = OperationQueue()
        task.expirationHandler = {
            #if DEBUG
            print("[AppDelegate] handleAppRefresh expirationHandler called → cancelAllOperations")
            #endif
            queue.cancelAllOperations()
        }

        let op = BlockOperation {
            // 가벼운 작업: METAR/TAF 짧은 호출, 위젯 타임라인 갱신, 캘린더 캐시 리프레시 등
            NotificationCenter.default.post(name: .cloudKitUpdated, object: nil)
            #if DEBUG
            print("[AppDelegate] .cloudKitUpdated posted from handleAppRefresh")
            #endif
        }

        op.completionBlock = {
            let success = !op.isCancelled
            #if DEBUG
            print("[AppDelegate] handleAppRefresh completed. success=\(success)")
            #endif
            task.setTaskCompleted(success: success)
        }

        queue.addOperation(op)
    }

    private func handleProcessing(task: BGProcessingTask) {
        #if DEBUG
        print("[AppDelegate] handleProcessing started")
        #endif

        // 다음 기회 재스케줄
        scheduleProcessing()

        var success = true

        task.expirationHandler = {
            // 오래 걸리는 처리 취소/정리
            #if DEBUG
            print("[AppDelegate] handleProcessing expirationHandler called")
            #endif
            success = false
        }

        // 무거운 작업: XLSX/PDF 임포트 큐 소화, CrewList 병합, Report/Debrief/FH 후처리, 캐시 인덱싱 등
        // 화면/모듈과의 연결은 알림으로 트리거
        NotificationCenter.default.post(name: .bgProcessingRequested, object: nil)
        #if DEBUG
        print("[AppDelegate] .bgProcessingRequested posted from handleProcessing")
        #endif

        task.setTaskCompleted(success: success)

        #if DEBUG
        print("[AppDelegate] handleProcessing completed. success=\(success)")
        #endif
    }

    // MARK: - UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration",
                                    sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // 필요 시 정리 작업
        #if DEBUG
        print("[AppDelegate] didDiscardSceneSessions: \(sceneSessions.count) sessions")
        #endif
    }

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
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}
