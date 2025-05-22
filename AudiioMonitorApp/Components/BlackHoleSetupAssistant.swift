import SwiftUI

struct BlackHoleSetupAssistant: View {
    @State private var step: Int = 1

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                Text("🔊 System Audio Monitoring Setup")
                    .font(.largeTitle.bold())
                    .padding(.top)

                switch step {
                    case 1:
                        StepView(title: "Step 1: Install BlackHole", description: "Download BlackHole from the official GitHub page.", link: "https://github.com/ExistentialAudio/BlackHole")
                    case 2:
                        StepView(title: "Step 2: Open Audio MIDI Setup", description: "Use Spotlight or Finder to launch the 'Audio MIDI Setup' app on your Mac.")
                    case 3:
                        StepView(title: "Step 3: Create Multi-Output Device", description: "In Audio MIDI Setup, create a Multi-Output Device combining BlackHole and your regular output (like headphones or speakers).")
                    case 4:
                        StepView(title: "Step 4: Route System Audio", description: "Go to System Settings > Sound and set the output device to the Multi-Output Device you created.")
                    case 5:
                        StepView(title: "Step 5: Select BlackHole in App", description: "Open this app's input device picker and choose BlackHole to start monitoring system audio.")
                    default:
                        Text("✅ Setup complete! You are now monitoring system audio.")
                            .font(.title2)
                            .padding()
                }

                Spacer()

                HStack {
                    if step > 1 {
                        Button("Back") {
                            step -= 1
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()

                    if step < 5 {
                        Button("Next") {
                            step += 1
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Finish") {
                            step += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
    }
}

struct StepView: View {
    let title: String
    let description: String
    var link: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            Text(description)
            if let link = link, let url = URL(string: link) {
                Link("Open Link", destination: url)
                    .font(.callout)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
    }
}

#Preview {
    BlackHoleSetupAssistant()
}
