//
//  PersistenceManager.swift
//  
//
//  Created by CS Kashyap on 5/8/23.
//

import Foundation

class PersistenceManager {
    private let objective: String
    
    private var currentSteps: [String?] = []
    
    private var knownStepsForObjective: [String?] {
        guard let allTests = UserDefaults.standard.object(forKey: Constants.userDefaultsKey) as? [String: [String?]], let stepsForObjective = allTests[objective] else { return [] }
        return stepsForObjective
    }
    
    init(objective: String) {
        self.objective = objective
        
        addObjectiveIfRequired()
    }
    
    private func addObjectiveIfRequired() {
        let userDefaults = UserDefaults.standard
        
        if userDefaults.object(forKey: Constants.userDefaultsKey) as? [String: [String?]] == nil
        {
            userDefaults.set([objective: [String?]()], forKey: Constants.userDefaultsKey)
        }
    }
    
    func getStep(index: Int) -> String? {
        let steps = knownStepsForObjective
        
        guard !steps.isEmpty, steps.count > index
        else { return nil }
            
        return steps[index]
    }
    
    func recordStep(_ value: String?) {
        currentSteps.append(value)
    }
    
    func persistSteps() {
        guard var allTests = UserDefaults.standard.object(forKey: Constants.userDefaultsKey) as? [String: [String?]], !currentSteps.isEmpty else { return }
        
        allTests[objective] = currentSteps
        UserDefaults.standard.set(allTests, forKey: Constants.userDefaultsKey)
    }
}

private enum Constants {
    static let userDefaultsKey = "TestPilotSteps"
}
