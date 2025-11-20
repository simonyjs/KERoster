//
//  LoginViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 11/20/25.
//

import UIKit

protocol LoginViewControllerDelegate: AnyObject {
    func loginInfoDidSave()
}

final class LoginViewController: UIViewController {
    
    // ✅ ViewController에서 받을 delegate
    weak var delegate: LoginViewControllerDelegate?
    
    // MARK: - UI (모두 코드로 생성)
    
    private let usernameTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "iFlight ID"
        tf.borderStyle = .roundedRect
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.returnKeyType = .next
        tf.textContentType = .username
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    
    private let passwordTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Password"
        tf.borderStyle = .roundedRect
        tf.isSecureTextEntry = true
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.returnKeyType = .done
        tf.textContentType = .password
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Enter your iFlight ID and password.\n Once you save, they will be automatically filled in for you in the future."
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Save", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "iFlight Login"
        view.backgroundColor = .systemBackground
        
        // 닫기 버튼 (모달로 띄운다고 가정)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        // 저장된 ID 목록 버튼
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Saved IDs",
            style: .plain,
            target: self,
            action: #selector(showSavedAccounts)
        )
        
        setupLayout()
        setupActions()
        loadSavedIfAny()
    }
    
    // MARK: - UI 배치
    
    private func setupLayout() {
        let stack = UIStackView(arrangedSubviews: [
            usernameTextField,
            passwordTextField,
            statusLabel,
            saveButton
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stack)
        
        let guide = view.safeAreaLayoutGuide
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            
            usernameTextField.heightAnchor.constraint(equalToConstant: 40),
            passwordTextField.heightAnchor.constraint(equalToConstant: 40),
            saveButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupActions() {
        saveButton.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - 기존 저장값 불러오기
    
    private func loadSavedIfAny() {
        let defaults = UserDefaults.standard
        let savedUser = defaults.string(forKey: "iFlightUsername") ?? ""
        
        usernameTextField.text = savedUser
        
        if savedUser.isEmpty {
            statusLabel.text = "Enter your iFlight ID and password.\n Once you save, they will be automatically filled in for you in the future."
            statusLabel.textColor = .secondaryLabel
            passwordTextField.text = nil
        } else {
            statusLabel.text = "Saved IDs: \(savedUser)"
            statusLabel.textColor = .secondaryLabel
            
            // 저장된 ID가 있으면 키체인에서 비밀번호도 같이 불러오기
            if let pw = KeychainService.loadPassword(account: savedUser) {
                passwordTextField.text = pw
            } else {
                passwordTextField.text = nil
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func saveButtonTapped() {
        let username = (usernameTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordTextField.text ?? ""
        
        guard !username.isEmpty, !password.isEmpty else {
            statusLabel.text = "Enter ID & P/W"
            statusLabel.textColor = .systemRed
            return
        }
        
        // 1) UserDefaults에 ID 저장 (자동 채우기용 기본 ID)
        let defaults = UserDefaults.standard
        defaults.set(username, forKey: "iFlightUsername")
        
        // 2) Keychain에 비밀번호 저장 (동일 account면 덮어쓰기)
        let saved = KeychainService.savePassword(password, account: username)
        
        if saved {
            statusLabel.textColor = .systemGreen
            statusLabel.text = "Save complete.\n After that, it will be automatically filled in on the iFlight login page."
            passwordTextField.text = ""
            
            // ✅ 메인 화면에게 "저장됨" 알리기
            delegate?.loginInfoDidSave()
            
            // ✅ 팝업 닫기
            dismiss(animated: true)
        } else {
            statusLabel.textColor = .systemRed
            statusLabel.text = "Saving failed. Please try again."
        }
    }
    
    // MARK: - Saved IDs 목록 화면
    
    @objc private func showSavedAccounts() {
        let vc = SavedAccountsViewController()
        vc.onSelectAccount = { [weak self] account in
            guard let self = self else { return }
            
            // 선택된 계정으로 필드 채우기
            self.usernameTextField.text = account
            if let pw = KeychainService.loadPassword(account: account) {
                self.passwordTextField.text = pw
            } else {
                self.passwordTextField.text = nil
            }
            
            self.statusLabel.textColor = .secondaryLabel
            self.statusLabel.text = "Selected ID: \(account)"
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}
