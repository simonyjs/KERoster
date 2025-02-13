//
//  ColdTempCorrectionViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/12.
//

import UIKit

class ColdTempCorrectionViewController: UIViewController {
    
    // UI 요소들
    @IBOutlet weak var temperatureTextField: UITextField!   // 기준 온도 입력 필드
    @IBOutlet weak var airportAltitudeTextField: UITextField! // 공항 표고 입력 필드
    // 수정할 고도 10개를 연결할 아울렛입니다.
    // 스토리보드에서 이 아울렛에 10개의 UITextField가 올바르게 연결되어 있는지 확인하세요.
    @IBOutlet var altitudeTextFields: [UITextField]!
    @IBOutlet weak var resultLabel: UILabel!                // 결과 표시 레이블

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 네비게이션 바 제목 설정
        self.navigationItem.title = "COLD TEMPERATURE CORRECTION"
    }
    
    // 계산 버튼 액션
    @IBAction func calculateButtonTapped(_ sender: UIButton) {
        // 온도와 공항 표고 입력값 확인 (문자열을 Double로 변환)
        guard let temperatureText = temperatureTextField.text,
              let temperature = Double(temperatureText),
              let airportAltitudeText = airportAltitudeTextField.text,
              let airportAltitude = Double(airportAltitudeText) else {
            resultLabel.text = "Invalid input"  // 입력값이 유효하지 않으면 메시지 출력
            return
        }
        
        // 수정할 고도들을 저장할 배열 (사용자가 입력한 값 중 빈 값은 무시)
        var altitudes: [Double] = []
        
        // altitudeTextFields 배열에 연결된 각 UITextField에서 값을 읽어옵니다.
        for altitudeTextField in altitudeTextFields {
            // 텍스트 필드의 text 프로퍼티는 옵셔널(String?)이므로 옵셔널 바인딩 후, 빈 문자열이 아니고 Double로 변환 가능한 경우만 추가
            if let altitudeText = altitudeTextField.text,
               !altitudeText.isEmpty,
               let altitude = Double(altitudeText) {
                altitudes.append(altitude)
            }
        }
        
        // 하나라도 고도 값이 입력되어 있어야 계산 진행
        if altitudes.isEmpty {
            resultLabel.text = "Please enter at least one altitude."
            return
        }
        
        // 보정된 고도를 저장할 배열
        var correctedAltitudes: [Double] = []
        let correctionCalculator = TemperatureCorrection()  // 보정 계산기 객체 생성
        
        // 각 입력된 고도에 대해 보정값을 계산
        for altitude in altitudes {
            let correctedAltitude = correctionCalculator.getAltitudeCorrection(temperature: Int(temperature),
                                                                                 airportAltitude: Int(airportAltitude),
                                                                                 targetAltitude: Int(altitude))
            correctedAltitudes.append(Double(correctedAltitude))
        }
        
        // 결과 문자열 구성 (각 고도별 보정 결과를 줄 단위로 추가)
        var resultText = "Corrected Altitudes:\n"
        for (index, correctedAltitude) in correctedAltitudes.enumerated() {
            resultText += "For Altitude \(altitudes[index]) ft: Corrected Altitude = \(correctedAltitude) ft\n"
        }
        
        // 구성된 결과 문자열을 레이블에 표시
        resultLabel.text = resultText
    }
}

// TemperatureCorrection 구조체
// 주어진 온도와 고도에 따라 보정값을 계산하는 역할을 합니다.
struct TemperatureCorrection {
    // 온도 레벨 (°C)
    let temperatureLevels: [Int] = [0, -10, -20, -30, -40, -50]
    // HAT(Height Above Terrain) 레벨 (ft)
    let HATLevels: [Int] = [200, 300, 400, 500, 600, 700, 800, 900, 1000, 1500, 2000, 3000, 4000, 5000]
    
    // 보정값 테이블 (각 행은 온도, 각 열은 HAT에 대한 보정값)
    let correctionTable: [[Int]] = [
        [20, 20, 30, 30, 40, 40, 50, 50, 60, 90, 120, 170, 230, 280],   // 0°C
        [20, 30, 40, 50, 60, 70, 80, 90, 100, 150, 200, 290, 390, 490],   // -10°C
        [30, 50, 60, 70, 90, 100, 120, 130, 140, 210, 280, 420, 570, 710], // -20°C
        [40, 60, 80, 100, 120, 140, 150, 170, 190, 280, 380, 570, 720, 950], // -30°C
        [50, 80, 100, 120, 150, 170, 190, 220, 240, 360, 480, 720, 970, 1210], // -40°C
        [60, 90, 120, 150, 180, 210, 240, 270, 300, 450, 590, 890, 1190, 1500]  // -50°C
    ]
    
    // 보정 고도를 계산하여 반환하는 함수
    func getAltitudeCorrection(temperature: Int, airportAltitude: Int, targetAltitude: Int) -> Int {
        // 온도 보정: 입력 온도보다 작거나 같은 가장 낮은 온도 레벨 선택
        let matchedTemp = temperatureLevels.last(where: { $0 <= temperature }) ?? temperatureLevels.first!
        
        // 고도 보정: 입력 고도에 해당하는 HAT 레벨 선택
        var matchedHAT = 0
        if targetAltitude <= 200 {
            matchedHAT = 200
        } else if targetAltitude <= 300 {
            matchedHAT = 300
        } else if targetAltitude <= 400 {
            matchedHAT = 400
        } else if targetAltitude <= 500 {
            matchedHAT = 500
        } else if targetAltitude <= 600 {
            matchedHAT = 600
        } else if targetAltitude <= 700 {
            matchedHAT = 700
        } else if targetAltitude <= 800 {
            matchedHAT = 800
        } else if targetAltitude <= 900 {
            matchedHAT = 900
        } else if targetAltitude <= 1000 {
            matchedHAT = 1000
        } else if targetAltitude <= 1500 {
            matchedHAT = 1500
        } else if targetAltitude <= 2000 {
            matchedHAT = 2000
        } else if targetAltitude <= 3000 {
            matchedHAT = 3000
        } else if targetAltitude <= 4000 {
            matchedHAT = 4000
        } else if targetAltitude <= 5000 {
            matchedHAT = 5000
        } else {
            matchedHAT = 5000
        }
        
        // 온도 및 HAT 레벨의 인덱스 확인
        guard let tempIndex = temperatureLevels.firstIndex(of: matchedTemp),
              let HATIndex1 = HATLevels.firstIndex(of: matchedHAT) else {
            return 0
        }
        
        // 첫 번째 보정값: 두 인덱스를 한 줄에 작성하여 하나의 표현식으로 만듭니다.
        let firstCorrection = correctionTable[min(tempIndex, correctionTable.count - 1)][min(HATIndex1, correctionTable[0].count - 1)]
        
        // 두 번째 보정값: 선택한 HAT보다 큰 다음 HAT 레벨의 값을 사용
        let nextHAT = HATLevels.first(where: { $0 > matchedHAT })
        var secondCorrection = 0
        if let nextHATValue = nextHAT, let HATIndex2 = HATLevels.firstIndex(of: nextHATValue) {
            secondCorrection = correctionTable[min(tempIndex, correctionTable.count - 1)][min(HATIndex2, correctionTable[0].count - 1)]
        }
        
        // 두 보정값 합산하여 반환
        return firstCorrection + secondCorrection
    }
}
