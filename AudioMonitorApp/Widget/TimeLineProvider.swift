//import WidgetKit
import SwiftUI

    // MARK: - Widget Entry

    /// `AudioStatsEntry` represents a single entry in the widget timeline.
    /// It includes the current timestamp and associated `AudioStats` data
    /// for rendering audio levels in the widget.
//struct AudioStatsEntry: TimelineEntry {
  //  let date: Date
        /// Captured audio statistics at the given timeline date.
        /// This includes left/right dBFS levels, input name, and device ID,
        /// used for rendering visual indicators in the widget.
  //  let stats: AudioStats
//}

    // MARK: - Timeline Provider

//struct AudioStatsProvider: TimelineProvider {
   // let appGroupID = "group.us.govango.AudioMonitor" // Replace if needed
   // let statsKey = "latestAudioStats"

   // func placeholder(in context: Context) -> AudioStatsEntry {
   //     AudioStatsEntry(date: Date(), stats: .preview)
   // }

   // func getSnapshot(in context: Context, completion: @escaping (AudioStatsEntry) -> Void) {
   //     let stats = loadStats() ?? .preview
    //    completion(AudioStatsEntry(date: Date(), stats: stats))
   /// }

  //  func getTimeline(in context: Context, completion: @escaping (Timeline<AudioStatsEntry>) -> Void) {
   //     let currentDate = Date()
   //     let stats = loadStats() ?? .preview
   ///     let entry = AudioStatsEntry(date: currentDate, stats: stats)

   //     print("🕒 [Widget] Timeline entry created with stats: \(stats)")

    //    let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(30)
   //     let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

 //       WidgetCenter.shared.reloadAllTimelines() // Force reload to refresh if real data arrives later
 //       completion(timeline)
  //  }

        // MARK: - Shared Storage Loading

        /// Attempts to load the most recent `AudioStats` object from shared UserDefaults.
        /// This data is shared via the App Group container between the main app and the widget.
        ///
        /// - Returns: A decoded `AudioStats` object if successful, or `nil` if unavailable or invalid.
//    private func loadStats() -> AudioStats? {
    //    guard let data = UserDefaults(suiteName: // appGroupID)?.data(forKey: statsKey) else {
     //       print("📦 [Widget] No shared data found for key: \(statsKey)")
   //         return nil
  //      }
   //     if let stats = try? JSONDecoder().decode(AudioStats.self, from: data) {
   //         print("📦 [Widget] Loaded stats: \(stats)")
  //          return stats
   //     } else {
   //         print("❌ [Widget] Failed to decode shared AudioStats data.")
   //         return nil
   //     }
//    }
//}
