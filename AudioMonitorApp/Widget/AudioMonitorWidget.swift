import WidgetKit
import SwiftUI
    //bundle: us.govango.AudioMonitorApp
    // widget extension: us.govango.AudioMonitorApp.AudioMonitorWidgetExtension

struct AudioMonitorEntry: TimelineEntry {
    let date: Date
    let leftLevel: Float
    let rightLevel: Float
}

struct AudioMonitorProvider: TimelineProvider {
    func placeholder(in context: Context) -> AudioMonitorEntry {
        AudioMonitorEntry(date: Date(), leftLevel: -20.0, rightLevel: -20.0)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (AudioMonitorEntry) ->()) {
        let entry = AudioMonitorEntry(date: Date(), leftLevel: -12.0, rightLevel: -12.0)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<AudioMonitorEntry>) -> ()) {
        let defaults = UserDefaults(suiteName: "group.us.govango.AudioMonitorApp")
        let left = defaults?.float(forKey: "leftLevel") ?? -80.0
        let right = defaults?.float(forKey: "rightLevel") ?? -80.0
        print("📦 Widget read: left = \(left), right = \(right)")
        
        let entry = AudioMonitorEntry(date: Date(), leftLevel: left, rightLevel: right)
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 15, to: Date()) ?? Date().addingTimeInterval(15)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct AudioMonitorWidgetEntryView : View {
    var entry: AudioMonitorProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
            case .systemSmall:
                VStack(spacing: 4) {
                    Text("L: \(Int(entry.leftLevel)) dBFS")
                    Text("R: \(Int(entry.rightLevel)) dBFS")
                    Text("Updated: \(entry.date.formatted(.dateTime.hour().minute().second()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .widgetURL(URL(string: "audiomonitorapp://"))
                
            case .systemMedium:
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Left")
                        Text("\(Int(entry.leftLevel)) dBFS")
                        Text("Updated: \(entry.date.formatted(.dateTime.hour().minute().second()))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Right")
                        Text("\(Int(entry.rightLevel)) dBFS")
                        Text("Updated: \(entry.date.formatted(.dateTime.hour().minute().second()))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .widgetURL(URL(string: "audiomonitorapp://"))
                
            default:
                VStack(spacing: 4) {
                    Text("L: \(Int(entry.leftLevel)) dBFS")
                    Text("R: \(Int(entry.rightLevel)) dBFS")
                    Text("Updated: \(entry.date.formatted(.dateTime.hour().minute().second()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .widgetURL(URL(string: "audiomonitorapp://"))
        }
    }
}


struct AudioMonitorWidget: Widget {
    let kind: String = "AudioMonitorWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AudioMonitorProvider()) { entry in
            if #available(macOS 14.0, *) {
                AudioMonitorWidgetEntryView(entry: entry)
                    .containerBackground(.background, for: .widget)
            } else {
                AudioMonitorWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Audio Monitor")
        .description("Shows recent dBFS levels for L/R input.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if os(macOS)
struct AudioMonitorWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AudioMonitorWidgetEntryView(
                entry: AudioMonitorEntry(
                    date: Date(),
                    leftLevel: -18.0,
                    rightLevel: -12.0
                )
            )
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("macOS Widget Small")
            
            AudioMonitorWidgetEntryView(
                entry: AudioMonitorEntry(
                    date: Date(),
                    leftLevel: -6.0,
                    rightLevel: -3.0
                )
            )
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("macOS Widget Medium")
        }
    }
}
#endif

    // Add widget instructions
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

struct AudioMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        AudioMonitorWidget()
    }
}
