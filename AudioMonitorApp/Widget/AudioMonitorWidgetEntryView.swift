import SwiftUI

//struct AudioMonitorWidgetEntryView : View {
//    var entry: AudioStatsEntry
//    @Environment(\.widgetFamily) var family
//    
//    var body: some View {
//        switch family {
//            case .systemSmall:
//                VStack(spacing: 4) {
//                    Text("L: \(Int(entry.stats.left)) dBFS")
//                    Text("R: \(Int(entry.stats.right)) dBFS")
//                    Text("Updated: \(entry.date.formatted(.dateTime.hour().minute().second()))")
//                        .font(.caption2)
//                        .foregroundColor(.secondary)
//                }
//                .padding()
//                .widgetURL(URL(string: "audiomonitorapp://"))
//                
//            case .systemMedium:
//                HStack {
//                    ChannelLevelView(label: "Left", value: entry.stats.left)
//                    Spacer()
//                    ChannelLevelView(label: "Right", value: entry.stats.right)
//                    VStack {
//                        Text("Updated: \(entry.date.formatted(.dateTime.hour().minute().second()))")
//                            .font(.caption2)
//                            .foregroundColor(.secondary)
//                    }
//                }
//                .padding()
//                .widgetURL(URL(string: "audiomonitorapp://"))
//                
//            default:
//                VStack(spacing: 4) {
//                    Text("L: \(Int(entry.stats.left)) dBFS")
//                    Text("R: \(Int(entry.stats.right)) dBFS")
//                    Text("Updated: \(entry.date.formatted(.dateTime.hour().minute().second()))")
//                        .font(.caption2)
//                        .foregroundColor(.secondary)
//                }
//                .padding()
//                .widgetURL(URL(string: "audiomonitorapp://"))
//        }
//    }
//}

//private struct ChannelLevelView: View {
//    let label: String
//    let value: Float
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            Text(label)
//            Text("\(Int(value)) dBFS")
//        }
//    }
//}
//#Preview {
//    AudioMonitorWidgetEntryView(entry: AudioStatsEntry(date: .now, stats: .preview))
//}
