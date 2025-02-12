//
//  ScheduleInputViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/12.
//

import UIKit

class ScheduleInputViewController: UIViewController, UITextFieldDelegate {
    
    // 전달받은 스케줄 데이터를 저장할 프로퍼티 (필요시 활용)
    var schedules: [String: [[String: String]]] = [:]
    // UserDefaults에 저장할 때 사용할 key
    let schedulesUserDefaultsKey = "schedules"
    
    // MARK: - UI Elements
    
    // 스크롤뷰 (키보드 입력 시 화면 스크롤 가능하도록)
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    // 모든 입력폼들을 담을 메인 스택뷰 (scrollView 내부에 추가)
    let mainStackView = UIStackView()
    
    // 근무타입 선택 (FLY, TVL, OTHER)
    let workTypeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["FLY", "TVL", "OTHER"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    // FLY/TVL 전용 입력필드
    let depDateTextField = UITextField()
    let arrDateTextField = UITextField()
    let itemTextField = UITextField()
    let depApTextField = UITextField()
    let depStnTimeTextField = UITextField()
    let arrApTextField = UITextField()
    let arrStnTimeTextField = UITextField()
    let flyingHoursTextField = UITextField()
    let dutyHoursTextField = UITextField()
    
    // OTHER 타입 입력필드
    // 시작 날짜, 종료 날짜, 액티비티, 근무 시작시간(DutyReport), 근무 종료시간(DutyDebrief)
    let dateTextField = UITextField()            // 시작 날짜
    let endDateTextField = UITextField()           // 종료 날짜
    let activityTextField = UITextField()
    let dutyReportTextField = UITextField()        // 근무 시작시간
    let dutyDebriefTextField = UITextField()       // 근무 종료시간
    
    // MARK: - View LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        self.title = "Add Schedule"
        
        setupScrollView()
        setupMainStackView()
        configureSegmentedControl()
        
        // 처음엔 FLY 타입 폼을 표시
        setupFlyTVLUI()
        
        // 저장 버튼 추가
        addSaveButton()
        
        // 키보드 옵저버 추가
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(notification:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(notification:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 스크롤뷰 및 스택뷰 설정
    
    func setupScrollView() {
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    func setupMainStackView() {
        mainStackView.axis = .vertical
        mainStackView.spacing = 16
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(mainStackView)
        
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            mainStackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            mainStackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            mainStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
        ])
    }
    
    // MARK: - 키보드 노티피케이션 메서드
    
    @objc func keyboardWillShow(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        scrollView.contentInset.bottom = keyboardFrame.height
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardFrame.height
    }
    
    @objc func keyboardWillHide(notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
    
    // MARK: - UI Setup Methods
    
    func configureSegmentedControl() {
        workTypeSegmentedControl.addTarget(self, action: #selector(workTypeChanged(_:)), for: .valueChanged)
        mainStackView.addArrangedSubview(workTypeSegmentedControl)
    }
    
    /// FLY 또는 TVL 타입 전용 입력폼 구성
    func setupFlyTVLUI() {
        configure(textField: depDateTextField, placeholder: "Dep Date (yyyy-MM-dd)")
        configure(textField: arrDateTextField, placeholder: "Arr Date (yyyy-MM-dd)")
        configure(textField: itemTextField, placeholder: "Item (C/S)")
        configure(textField: depApTextField, placeholder: "Dep Airport (IATA)")
        configure(textField: depStnTimeTextField, placeholder: "Dep Time (HH:mm)")
        configure(textField: arrApTextField, placeholder: "Arr Airport (IATA)")
        configure(textField: arrStnTimeTextField, placeholder: "Arr Time (HH:mm)")
        configure(textField: flyingHoursTextField, placeholder: "Flying Hours (HH:mm)")
        configure(textField: dutyHoursTextField, placeholder: "Duty Hours (HH:mm)")
        
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Dep Date", textField: depDateTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Arr Date", textField: arrDateTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Item", textField: itemTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Dep Airport", textField: depApTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Dep Time", textField: depStnTimeTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Arr Airport", textField: arrApTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Arr Time", textField: arrStnTimeTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Flying Hours", textField: flyingHoursTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Duty Hours", textField: dutyHoursTextField))
    }
    
    /// OTHER 타입 전용 입력폼 구성
    func setupOtherUI() {
        // OTHER 타입에서는 시작 날짜, 종료 날짜, 액티비티, 근무 시작시간, 근무 종료시간을 입력받습니다.
        configure(textField: dateTextField, placeholder: "Start Date (yyyy-MM-dd)")
        configure(textField: endDateTextField, placeholder: "End Date (yyyy-MM-dd)")
        configure(textField: activityTextField, placeholder: "Activity")
        configure(textField: dutyReportTextField, placeholder: "Start Time (HH:mm)")
        configure(textField: dutyDebriefTextField, placeholder: "End Time (HH:mm)")
        
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Start Date", textField: dateTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "End Date", textField: endDateTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Activity", textField: activityTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Start Time", textField: dutyReportTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "End Time", textField: dutyDebriefTextField))
    }
    
    /// 저장 버튼 추가 (맨 마지막에 배치)
    func addSaveButton() {
        let saveButton = UIButton(type: .system)
        saveButton.setTitle("Save Schedule", for: .normal)
        saveButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        saveButton.backgroundColor = UIColor.systemBlue
        saveButton.tintColor = .white
        saveButton.layer.cornerRadius = 5
        saveButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        mainStackView.addArrangedSubview(saveButton)
    }
    
    // MARK: - Helper Methods
    
    /// 텍스트필드 기본 설정
    func configure(textField: UITextField, placeholder: String) {
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.textColor = .black
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
    }
    
    /// 레이블과 텍스트필드를 포함하는 수평 스택뷰 생성
    func createLabeledField(labelText: String, textField: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = labelText
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .black
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        
        let hStack = UIStackView(arrangedSubviews: [label, textField])
        hStack.axis = .horizontal
        hStack.spacing = 8
        return hStack
    }
    
    // MARK: - Action Methods
    
    /// 근무타입 세그먼트 컨트롤 값 변경 시 호출
    @objc func workTypeChanged(_ sender: UISegmentedControl) {
        // 기존 입력폼들 모두 제거 (세그먼트 컨트롤과 저장 버튼은 제거하지 않음)
        mainStackView.arrangedSubviews.forEach { view in
            if view !== workTypeSegmentedControl {
                view.removeFromSuperview()
            }
        }
        
        // 선택한 근무타입에 따라 폼을 다시 구성
        let selectedType = workTypeSegmentedControl.titleForSegment(at: workTypeSegmentedControl.selectedSegmentIndex)
        if selectedType == "FLY" || selectedType == "TVL" {
            setupFlyTVLUI()
        } else {
            setupOtherUI()
        }
        
        // 마지막에 저장 버튼 추가
        addSaveButton()
    }
    
    /// 저장 버튼 탭 시 호출: 입력값 검증 후 스케줄 데이터를 생성하고 저장 처리
    @objc func saveTapped() {
        // 날짜 변환을 위한 DateFormatter 설정
        let inputDateFormatter = DateFormatter()
        inputDateFormatter.dateFormat = "yyyy-MM-dd"  // 사용자 입력 형식
        inputDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let outputDateFormatter = DateFormatter()
        outputDateFormatter.dateFormat = "dd-MMM-yyyy"  // 저장할 형식
        outputDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // 헬퍼 함수: HH:mm 형식 검증 (00:00 ~ 23:59)
        func isValidTime(_ time: String) -> Bool {
            let timeRegex = "^([01]\\d|2[0-3]):([0-5]\\d)$"
            let predicate = NSPredicate(format: "SELF MATCHES %@", timeRegex)
            return predicate.evaluate(with: time)
        }
        
        // 헬퍼 함수: 공항 코드는 3글자 대문자여야 함 (IATA 형식)
        func isValidAirportCode(_ code: String) -> Bool {
            let codeRegex = "^[A-Z]{3}$"
            let predicate = NSPredicate(format: "SELF MATCHES %@", codeRegex)
            return predicate.evaluate(with: code)
        }
        
        let selectedType = workTypeSegmentedControl.titleForSegment(at: workTypeSegmentedControl.selectedSegmentIndex) ?? "FLY"
        var schedule: [String: String] = [:]
        // "OTHER"인 경우에는 근무타입 값을 저장하지 않음
        if selectedType != "OTHER" {
            schedule["WorkType"] = selectedType
        }
        
        if selectedType == "FLY" || selectedType == "TVL" {
            // FLY/TVL 타입: 출발/도착 날짜, 공항, 시간 등 기존 로직
            guard let depDateInput = depDateTextField.text,
                  let depDate = inputDateFormatter.date(from: depDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid departure date in format yyyy-MM-dd.")
                return
            }
            guard let arrDateInput = arrDateTextField.text,
                  let arrDate = inputDateFormatter.date(from: arrDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid arrival date in format yyyy-MM-dd.")
                return
            }
            schedule["DepDate"] = outputDateFormatter.string(from: depDate)
            schedule["ArrDate"] = outputDateFormatter.string(from: arrDate)
            
            guard let depAp = depApTextField.text?.uppercased(), isValidAirportCode(depAp) else {
                showAlert(title: "Invalid Airport", message: "Please enter a valid departure airport code (3-letter IATA, uppercase).")
                return
            }
            guard let arrAp = arrApTextField.text?.uppercased(), isValidAirportCode(arrAp) else {
                showAlert(title: "Invalid Airport", message: "Please enter a valid arrival airport code (3-letter IATA, uppercase).")
                return
            }
            schedule["DepAp"] = depAp
            schedule["ArrAp"] = arrAp
            
            if let item = itemTextField.text, !item.isEmpty {
                schedule["Item"] = item.uppercased()
            }
            
            guard let depTime = depStnTimeTextField.text, isValidTime(depTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid departure time in format HH:mm.")
                return
            }
            guard let arrTime = arrStnTimeTextField.text, isValidTime(arrTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid arrival time in format HH:mm.")
                return
            }
            schedule["DepStnTime"] = depTime
            schedule["ArrStnTime"] = arrTime
            
            if let flyingHours = flyingHoursTextField.text, !flyingHours.isEmpty {
                if isValidTime(flyingHours) {
                    schedule["FlyingHours"] = flyingHours
                } else {
                    showAlert(title: "Invalid Time", message: "Please enter a valid Flying Hours in format HH:mm.")
                    return
                }
            }
            if let dutyHours = dutyHoursTextField.text, !dutyHours.isEmpty {
                if isValidTime(dutyHours) {
                    schedule["DutyHours"] = dutyHours
                } else {
                    showAlert(title: "Invalid Time", message: "Please enter a valid Duty Hours in format HH:mm.")
                    return
                }
            }
            
        } else {
            // OTHER 타입: 시작 날짜, 종료 날짜, 액티비티, 근무 시작시간, 근무 종료시간 처리
            guard let startDateInput = dateTextField.text,
                  let startDate = inputDateFormatter.date(from: startDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid start date in format yyyy-MM-dd.")
                return
            }
            guard let endDateInput = endDateTextField.text,
                  let endDate = inputDateFormatter.date(from: endDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid end date in format yyyy-MM-dd.")
                return
            }
            schedule["DepDate"] = outputDateFormatter.string(from: startDate)
            // 종료 날짜도 저장하여 달력에서 비교할 수 있도록 함
            schedule["DutyDebriefDate"] = outputDateFormatter.string(from: endDate)
            
            if let activity = activityTextField.text, !activity.isEmpty {
                schedule["Activity"] = activity.uppercased()
            }
            guard let startTime = dutyReportTextField.text, isValidTime(startTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid start time in format HH:mm.")
                return
            }
            schedule["DutyReport"] = startTime
            
            guard let endTime = dutyDebriefTextField.text, isValidTime(endTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid end time in format HH:mm.")
                return
            }
            let dayDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            if dayDiff > 0 {
                schedule["DutyDebrief"] = "\(endTime)(+\(dayDiff))"
            } else {
                schedule["DutyDebrief"] = endTime
            }
        }
        
        // ★ 스케줄 저장 로직 ★
        var savedSchedules = [String: [[String: String]]]()
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                savedSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            } catch {
                print("스케줄 로드 실패: \(error)")
            }
        }
        if let depDateKey = schedule["DepDate"] {
            savedSchedules[depDateKey, default: []].append(schedule)
        }
        do {
            let encodedData = try JSONEncoder().encode(savedSchedules)
            UserDefaults.standard.set(encodedData, forKey: schedulesUserDefaultsKey)
            print("Saved schedule: \(savedSchedules)")
        } catch {
            print("스케줄 저장 실패: \(error)")
        }
        
        let alert = UIAlertController(title: "Success", message: "Schedule saved successfully.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - Alert Helper
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
