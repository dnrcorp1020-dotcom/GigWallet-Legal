import SwiftUI

enum AnimationConstants {
    static let quick: Animation = .easeOut(duration: 0.15)
    static let standard: Animation = .easeInOut(duration: 0.25)
    static let smooth: Animation = .easeInOut(duration: 0.35)
    static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.75)
    static let bouncy: Animation = .spring(response: 0.5, dampingFraction: 0.6)
    static let slow: Animation = .easeInOut(duration: 0.6)

    // Counter animation
    static let counterDuration: Double = 1.2
    static let counterAnimation: Animation = .easeOut(duration: counterDuration)

    // Stagger
    static let staggerDelay: Double = 0.05
}
