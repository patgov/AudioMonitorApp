    //
    //  ThreadSafetyValidator.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 7/16/25.
    //

import Foundation

enum ThreadSafetyValidator {
    static func ensureMainThread(_ message: String = "Mutation must be on main thread") {
        assert(Thread.isMainThread, message)
    }

    @MainActor
    static func assertMainActor(_ message: String = "Must be on MainActor") {
        assert(Thread.isMainThread, message)
    }
}

struct ExampleOwner {
    var somePublishedVar = false
    
    func updatePublishedProperty() {
        ThreadSafetyValidator.ensureMainThread("Updating @Published var must happen on main thread")
        // Use mutating if this property needs to be changed on a struct
        // For a class, make the property 'var' and the method 'mutating' is not needed
        // Uncomment the next line if you want to change the property
        // self.somePublishedVar = true
    }
}
