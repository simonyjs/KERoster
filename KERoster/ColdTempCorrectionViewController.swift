import UIKit

class ColdTempCorrectionViewController: UIViewController {
    
    // UI 요소들
    @IBOutlet weak var temperatureTextField: UITextField!
    @IBOutlet weak var airportAltitudeTextField: UITextField!
    @IBOutlet var altitudeTextFields: [UITextField]!  // 10개의 수정할 고도를 받을 텍스트 필드
    @IBOutlet weak var resultLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    // ColdTempCorrection 계산을 위한 버튼 액션
    @IBAction func calculateButtonTapped(_ sender: UIButton) {
        guard let temperatureText = temperatureTextField.text,
              let temperature = Double(temperatureText),
              let airportAltitudeText = airportAltitudeTextField.text,
              let airportAltitude = Double(airportAltitudeText) else {
            resultLabel.text = "Invalid input"
            return
        }
        
        // 수정할 고도를 배열로 받기
        var altitudes: [Double] = []
        for altitudeTextField in altitudeTextFields {
            if let altitudeText = altitudeTextField.text, let altitude = Double(altitudeText) {
                altitudes.append(altitude)
            } else {
                resultLabel.text = "Please enter valid altitude values"
                return
            }
        }
        
        // 공항 표고와 온도에 따른 보정값 계산
        var correctedTemps: [Double] = []
        for altitude in altitudes {
            let correctedTemp = calculateColdTempCorrection(for: temperature, airportAltitude: airportAltitude, targetAltitude: altitude)
            correctedTemps.append(correctedTemp)
        }
        
        // 결과 표시 (고도별로 보정값을 나열)
        var resultText = "Corrected Temperatures:\n"
        for (index, correctedTemp) in correctedTemps.enumerated() {
            resultText += "Altitude \(altitudes[index]) ft: \(correctedTemp)°C\n"
        }
        
        resultLabel.text = resultText
    }
    
    // ColdTempCorrection 계산 로직 (공항 표고와 수정할 고도를 고려한 계산)
    func calculateColdTempCorrection(for temp: Double, airportAltitude: Double, targetAltitude: Double) -> Double {
        // 예시 로직: 공항 표고에 따라 수정값을 계산하고, 온도에 따른 보정값을 적용
        let altitudeCorrection = (targetAltitude - airportAltitude) * 0.001 // 예시: 고도 차이에 따라 보정
        var correctedTemp = temp + altitudeCorrection
        
        // 온도에 따른 보정값 적용
        if correctedTemp <= -21 {
            correctedTemp = -30
        } else if correctedTemp <= -29 {
            correctedTemp = -30
        } else if correctedTemp <= 1 {
            correctedTemp = 0
        }
        
        return correctedTemp
    }
}
