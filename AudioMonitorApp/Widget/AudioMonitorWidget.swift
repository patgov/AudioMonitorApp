import SwiftUI

    // Main widget configuration for the AudioMonitorWidget
//struct AudioMonitorWidget: Widget {
//    let kind: String = "AudioMonitorWidget"
//    
//    var body: some WidgetConfiguration {
//            // Uses a static configuration with a provider and entry view
//        StaticConfiguration(kind: kind, provider: AudioStatsProvider()) { entry in
//            if #available(macOS 14.0, *) {
//                    // macOS 14+ allows containerBackground customization
//                AudioMonitorWidgetEntryView(entry: entry)
//                    .containerBackground(.background, for: .widget)
//            } else {
//                AudioMonitorWidgetEntryView(entry: entry)
//            }
//        }
//        .configurationDisplayName("Audio Monitor")
//        .description("Shows recent dBFS levels for L/R input.")
//        .supportedFamilies([.systemSmall, .systemMedium])
//    }
//}

//#if os(macOS)
    // Widget previews are often unsupported on macOS, especially for extensions.
    // Xcode may fail to launch the widget preview due to platform restrictions.
//struct AudioMonitorWidget_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
                // Example of a small widget preview
//            AudioMonitorWidgetEntryView(
//                entry: AudioStatsEntry(
//                    date: Date(),
//                    stats: AudioStats(left: -18.0, right: -12.0, inputName: "PreviewMic", inputID: 1)
//                )
//            )
//            .previewContext(WidgetPreviewContext(family: .systemSmall))
//            .previewDisplayName("macOS Widget Small")
//            
//                // Example of a medium widget preview
//            AudioMonitorWidgetEntryView(
//                entry: AudioStatsEntry(
//                    date: Date(),
//                    stats: AudioStats(left: -6.0, right: -3.0, inputName: "PreviewMic", inputID: 1)
//                )
//            )
//            .previewContext(WidgetPreviewContext(family: .systemMedium))
//            .previewDisplayName("macOS Widget Medium")
//        }
//    }
//}
//#endif

    // Required for WidgetKit bundle declaration
//struct AudioMonitorWidgetBundle: WidgetBundle {
//    var body: some Widget {
//        AudioMonitorWidget()
//    }
//}
