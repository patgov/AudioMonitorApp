//
//  WidgetOnboardingView.swift
//  AudioMonitorApp
//
//  Created by Pat Govan on 6/8/25.
//

import SwiftUI

struct WidgetOnboardingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("📡 Add the Audio Monitor Widget")
                .font(.title2)
                .bold()

            Text("You can monitor audio levels directly from your desktop with the Audio Monitor widget.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("➊ Run this app once.")
                Text("➋ Right-click your desktop.")
                Text("➌ Select “Edit Widgets”.")
                Text("➍ Search for “Audio Monitor” and click ➕ to add.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(10)

            Button("Open Widget Gallery") {
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-b", "com.apple.notificationcenterui"]
                try? task.run()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    WidgetOnboardingView()
}
