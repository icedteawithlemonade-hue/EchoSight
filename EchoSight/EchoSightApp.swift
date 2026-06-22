//
//  EchoSightApp.swift
//  EchoSight
//
//  Created by Ram Verma on 1/28/26.
//

import SwiftUI

// App entry point.
// SwiftUI starts here, then hands control to RootView in OnboardingFlow.swift.
// RootView decides whether the user sees loading, onboarding, or the main app.
@main
struct EchoSightApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
