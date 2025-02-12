//
//  ColdTempCorrectionViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/12.
//

import UIKit

class ColdTempCorrectionViewController: UIViewController {
    
    // UI 요소들
    @IBOutlet weak var temperatureTextField: UITextField!  // 기준 온도
    @IBOutlet weak var airportAltitudeTextField: UITextField!  // 공항 표고
    @IBOutlet var altitudeTextFields: [UITextField]!  // 수정할 고도 10개
    @IBOutlet weak var resultLabel: UILabel!  // 결과 표시

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 네비게이션 바 제목 설정
        self.navigationItem.title = "COLD TEMPERATURE CORRECTION"
    }
    
    // ColdTempCorrection 계산을 위한 버튼 액션
    @IBAction func calculateButtonTapped(_ sender: UIButton) {
        // 공항 표고와 온도 입력 확인
        guard let temperatureText = temperatureTextField.text,
              let temperature = Double(temperatureText),
              let airportAltitudeText = airportAltitudeTextField.text,
              let airportAltitude = Double(airportAltitudeText) else {
            resultLabel.text = "Invalid input"
            return
        }
        
        // 수정할 고도 10개 배열로 받기
        var altitudes: [Double] = []
        for altitudeTextField in altitudeTextFields {
            if let altitudeText = altitudeTextField.text, let altitude = Double(altitudeText) {
                altitudes.append(altitude)
            } else {
                resultLabel.text = "Please enter valid altitude values for all 10 altitudes."
                return
            }
        }
        
        // 공항 표고와 온도에 따른 보정 고도 계산
        var correctedAltitudes: [Double] = []
        let correctionCalculator = TemperatureCorrection()
        
        for altitude in altitudes {
            let correctedAltitude = correctionCalculator.getAltitudeCorrection(temperature: Int(temperature), airportAltitude: Int(airportAltitude), targetAltitude: Int(altitude))
            correctedAltitudes.append(Double(correctedAltitude))
        }
        
        // 결과 표시 (고도별로 보정된 고도 값 출력)
        var resultText = "Corrected Altitudes:\n"
        for (index, correctedAltitude) in correctedAltitudes.enumerated() {
            resultText += "For Altitude \(altitudes[index]) ft: Corrected Altitude = \(correctedAltitude) ft\n"
        }
        
        resultLabel.text = resultText
    }
}

// TemperatureCorrection 구조체를 ColdTempCorrectionViewController.swift 안에 포함시킴
struct TemperatureCorrection {
    // 표의 온도 값 (°C)
    let temperatureLevels: [Int] = [0, -10, -20, -30, -40, -50]
    
    // 표의 HAT 값 (ft)
    let HATLevels: [Int] = [200, 300, 400, 500, 600, 700, 800, 900, 1000, 1500, 2000, 3000, 4000, 5000]
    
    // 보정값 테이블 (각 행은 온도, 각 열은 HAT에 대한 보정값)
    let correctionTable: [[Int]] = [
        [20, 20, 30, 30, 40, 40, 50, 50, 60, 90, 120, 170, 230, 280],  // 0°C
        [20, 30, 40, 50, 60, 70, 80, 90, 100, 150, 200, 290, 390, 490],  // -10°C
        [30, 50, 60, 70, 90, 100, 120, 130, 140, 210, 280, 420, 570, 710],  // -20°C
        [40, 60, 80, 100, 120, 140, 150, 170, 190, 280, 380, 570, 720, 950],  // -30°C
        [50, 80, 100, 120, 150, 170, 190, 220, 240, 360, 480, 720, 970, 1210],  // -40°C
        [60, 90, 120, 150, 180, 210, 240, 270, 300, 450, 590, 890, 1190, 1500]  // -50°C
    ]
    
    // 보정 고도를 반환하는 함수
    func getAltitudeCorrection(temperature: Int, airportAltitude: Int, targetAltitude: Int) -> Int {
        // 온도 보정 (더 낮은 온도로 적용)
        let matchedTemp = temperatureLevels.last(where: { $0 <= temperature }) ?? temperatureLevels.first!
        
        // 고도 보정 (각 고도 구간에 맞춰 값 적용)
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

        // 고도의 두 값을 찾아서 합산 (표에서 가장 가까운 고도와 그보다 높은 고도)
        guard let tempIndex = temperatureLevels.firstIndex(of: matchedTemp),
              let HATIndex1 = HATLevels.firstIndex(of: matchedHAT) else {
            return 0
        }
        
        // 첫 번째 고도에 대한 보정값
        let firstCorrection = correctionTable[min(tempIndex, correctionTable.count - 1)][min(HATIndex1, correctionTable[0].count - 1)]
        
        // 두 번째 고도 (그보다 높은 고도)
        let nextHAT = HATLevels.first(where: { $0 > matchedHAT })
        var secondCorrection = 0
        if let nextHATValue = nextHAT, let HATIndex2 = HATLevels.firstIndex(of: nextHATValue) {
            secondCorrection = correctionTable[min(tempIndex, correctionTable.count - 1)][min(HATIndex2, correctionTable[0].count - 1)]
        }
        
        // 두 고도의 보정값 합산
        return firstCorrection + secondCorrection
    }
}
