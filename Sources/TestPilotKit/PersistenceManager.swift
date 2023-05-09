//
//  PersistenceManager.swift
//  
//
//  Created by CS Kashyap on 5/8/23.
//

import Foundation

class PersistenceManager {
    private let objective: String
    private let shouldRecordSteps: Bool
    
    private var knownStepsForObjective: [String?] {
        guard let allSteps = UserDefaults.standard.object(forKey: Constants.userDefaultsKey) as? [String: [String?]], let stepsForObjective = allSteps[objective] else { return [] }
        return stepsForObjective
    }
    
    init(objective: String,
         shouldRecordSteps: Bool
    ) {
        self.objective = objective
        self.shouldRecordSteps = shouldRecordSteps
        
        addObjectiveIfRequired()
    }
    
    private func addObjectiveIfRequired() {
        let userDefaults = UserDefaults.standard
        
        if userDefaults.object(forKey: Constants.userDefaultsKey) as? [String: [String?]] == nil
        {
            userDefaults.set([objective: [String?]()], forKey: Constants.userDefaultsKey)
        }

        // Clear the previously stored steps if this run needs to be recorded.
        guard shouldRecordSteps else { return }
        
        updateStepsForObjective([])
    }
    
    func getStep(index: Int) -> String? {
        let steps = knownStepsForObjective
        
        guard !steps.isEmpty, steps.count > index
        else { return nil }
            
        return steps[index]
    }
    
    func updateStep(index: Int, value: String?) {
        var stepsForObjective = knownStepsForObjective
        
        stepsForObjective.append(value)
        
        updateStepsForObjective(stepsForObjective)
    }
    
    private func updateStepsForObjective(_ steps: [String?]) {
        guard var allSteps = UserDefaults.standard.object(forKey: Constants.userDefaultsKey) as? [String: [String?]] else { return }
        
        allSteps[objective] = steps
        UserDefaults.standard.set(allSteps, forKey: Constants.userDefaultsKey)
    }
}

private enum Constants {
    static let userDefaultsKey = "TestPilotSteps"
}
