//
//  AppDelegate.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/22.
//

import UIKit
import CoreData
import Foundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
         sleep(1)


        // iCloud KVS: 앱 시작 시 동기화
        NSUbiquitousKeyValueStore.default.synchronize()

        // 외부(iCloud) 변경 → 앱 내부로 브로드캐스트
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { note in
            // (선택) 어떤 키가 바뀌었는지 로그
            if let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
                print("[KVS] changed keys: \(keys)")
            }
            NotificationCenter.default.post(name: Notification.Name("KVSUpdated"), object: nil)
        }

        return true
    }

    // 포그라운드 복귀 시 동기화 한 번 더 (다른 기기에서 바뀐 값 당겨오기)
    func applicationDidBecomeActive(_ application: UIApplication) {
        NSUbiquitousKeyValueStore.default.synchronize()
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


