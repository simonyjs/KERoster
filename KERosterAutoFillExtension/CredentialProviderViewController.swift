//
//  CredentialProviderViewController.swift
//  KERosterAutoFillExtension
//
//  Created by 윤정섭 on 11/20/25.
//

import AuthenticationServices
import Foundation

class CredentialProviderViewController: ASCredentialProviderViewController {

    private var credentials: [KERosterCredential] = []

    // MARK: - 목록 준비 (키보드 위 '암호' 버튼을 눌렀을 때)

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // App Group 에서 저장된 계정들 로드
        credentials = KERosterCredentialStore.shared.loadAll()

        // 여기서 serviceIdentifiers 를 보고 도메인 필터링도 가능하지만,
        // 지금은 전체 계정을 대상으로 둬도 동작에는 문제 없음.
        //
        // 만약 스토리보드에 테이블뷰/컬렉션뷰 연결했다면 여기서 reloadData().
        //
        // tableView.reloadData()
    }

    // MARK: - QuickType: 사용자 상호작용 없이 바로 제공

    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        guard let cred = KERosterCredentialStore.shared
            .credential(for: credentialIdentity.recordIdentifier) else {

            // 저장된 계정을 못 찾았으니 UI 띄워달라고 요청
            let error = NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue,
                userInfo: nil
            )
            extensionContext.cancelRequest(withError: error)
            return
        }

        let passwordCredential = ASPasswordCredential(
            user: cred.username,
            password: cred.password
        )

        extensionContext.completeRequest(
            withSelectedCredential: passwordCredential,
            completionHandler: nil
        )
    }

    // MARK: - QuickType 실패 시, 확장 UI 띄운 경우

    override func prepareInterfaceToProvideCredential(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        // 여기서는 Face ID 확인 / 계정 선택 UI 등을 띄울 수 있음.
        // 간단 버전: 바로 제공

        guard let cred = KERosterCredentialStore.shared
            .credential(for: credentialIdentity.recordIdentifier) else {

            let error = NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: nil
            )
            extensionContext.cancelRequest(withError: error)
            return
        }

        let passwordCredential = ASPasswordCredential(
            user: cred.username,
            password: cred.password
        )

        extensionContext.completeRequest(
            withSelectedCredential: passwordCredential,
            completionHandler: nil
        )
    }

    // MARK: - UI에서 버튼 눌렀을 때(선택된 계정 사용)

    @IBAction func passwordSelected(_ sender: AnyObject?) {
        // 예시: 일단 첫 번째 계정을 사용
        guard let cred = credentials.first else {
            let error = NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: nil
            )
            extensionContext.cancelRequest(withError: error)
            return
        }

        let passwordCredential = ASPasswordCredential(
            user: cred.username,
            password: cred.password
        )

        extensionContext.completeRequest(
            withSelectedCredential: passwordCredential,
            completionHandler: nil
        )
    }

    @IBAction func cancel(_ sender: AnyObject?) {
        let error = NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userCanceled.rawValue,
            userInfo: nil
        )
        extensionContext.cancelRequest(withError: error)
    }
}
