//
//  AppLockManager.swift
//  KERoster
//
//  Created by 윤정섭 on 11/20/25.
//

import Foundation
import LocalAuthentication
import UIKit

final class AppLockManager {
    static let shared = AppLockManager()
    private init() {}

    // 이 세션에서 이미 통과했는지 (앱 켜져 있는 동안 한 번만 묻고 싶으면 사용)
    private var hasUnlockedThisSession = false

    /// 필요할 때만(아직 안 풀렸으면) 인증 실행
    func authenticateIfNeeded(completion: @escaping (Bool) -> Void) {
        if hasUnlockedThisSession {
            completion(true)
            return
        }

        let context = LAContext()
        var error: NSError?

        // Face ID/Touch ID + 기기 암호 모두 허용
        let policy: LAPolicy = .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            // 바이오메트릭/암호 사용 불가한 기기면 그냥 통과시킬지, 막을지 선택
            print("⚠️ LocalAuthentication not available: \(error?.localizedDescription ?? "Unknown error")")
            completion(true) // 여기서 false로 바꾸면 그런 기기에서는 아예 사용 못하게 할 수도 있음
            return
        }

        let reason = "Authentication is required to protect your KERoster information."

        context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, evalError in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    print("✅ AppLock 인증 성공")
                    self.hasUnlockedThisSession = true
                    completion(true)
                } else {
                    let nsError = evalError as NSError?
                    print("❌ AppLock 인증 실패: \(nsError?.localizedDescription ?? "Unknown")")

                    // 원하는 동작 정의: 여기서는 false만 전달
                    completion(false)

                    // 예: 사용자가 취소하면 앱을 백그라운드로 내리기
                    if let code = nsError?.code,
                       code == LAError.userCancel.rawValue ||
                       code == LAError.systemCancel.rawValue {
                        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                    }
                }
            }
        }
    }

    /// 다음 포그라운드에서 다시 물어보고 싶을 때 세션 리셋
    func resetSession() {
        hasUnlockedThisSession = false
    }
}
