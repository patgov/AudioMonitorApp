    //
    //  AudioMonitorWidget.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 6/2/25.
    //

import WidgetKit
import SwiftUI

struct AudioMonitorEntry: TimelineEntry {
    let date: Date
    let leftLevel: Float
    let rightLevel: Float
}

struct AudioMonitorProvider: TimelineProvider {
    func placeholder(in context: Context) -> AudioMonitorEntry {
        AudioMonitorEntry(date: Date(), leftLevel: -20.0, rightLevel: -20.0)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (AudioMonitorEntry) -> ()) {
        let entry = AudioMonitorEntry(date: Date(), leftLevel: -12.0, rightLevel: -12.0)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<AudioMonitorEntry>) -> ()) {
        let defaults = UserDefaults(suiteName: "group.com.yourcompany.AudiioMonitorApp")
        let left = defaults?.float(forKey: "leftLevel") ?? -80.0
        let right = defaults?.float(forKey: "rightLevel") ?? -80.0
        
        let entry = AudioMonitorEntry(date: Date(), leftLevel: left, rightLevel: right)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
        completion(timeline)
    }
}

struct AudioMonitorWidgetEntryView : View {
    var entry: AudioMonitorProvider.Entry
    
    var body: some View {
        VStack {
            Text("L: \(Int(entry.leftLevel)) dBFS")
            Text("R: \(Int(entry.rightLevel)) dBFS")
        }
        .padding()
        .widgetURL(URL(string: "audiomonitorapp://"))
    }
}


@main
struct AudioMonitorWidget: Widget {
    let kind: String = "AudioMonitorWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AudioMonitorProvider()) { entry in
            AudioMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Audio Monitor")
        .description("Shows recent dBFS levels for L/R input.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AudioMonitorWidget_Previews: PreviewProvider {
    static var previews: some View {
        AudioMonitorWidgetEntryView(
            entry: AudioMonitorEntry(
                date: Date(),
                leftLevel: -18.0,
                rightLevel: -12.0
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
