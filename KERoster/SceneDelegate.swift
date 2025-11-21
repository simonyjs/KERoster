//
//  SceneDelegate.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/22.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // 스토리보드(Main)를 사용하는 경우, 기본 설정 그대로
        guard let _ = (scene as? UIWindowScene) else { return }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // 백그라운드로 간 뒤 다시 연결되지 않을 수도 있을 때 호출
        // 여기서는 따로 처리할 내용 없음
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        CloudKitManager.shared.forceSync()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // active → inactive로 갈 때 (전화 수신 등)
        // 예전 KVS 관련 코드는 전부 삭제
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // background → foreground로 올라올 때
        // 잠금 로직은 ViewController.viewDidAppear + AppLockManager에서 처리하므로 여기선 할 일 없음
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // foreground → background로 내려갈 때 호출

        // CoreData 등 저장
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()

        // 다음에 다시 올라올 때는 다시 인증 받도록 세션 리셋
        AppLockManager.shared.resetSession()
    }
}
