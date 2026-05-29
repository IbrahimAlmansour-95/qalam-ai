import Foundation
import AppKit

/// Expands dynamic placeholders inside snippet expansions:
///   {date}  / :date:   → today's date (medium)
///   {time}  / :time:   → current time (short)
///   {datetime}         → date + time
///   {clipboard}        → current clipboard text
enum SnippetVariables {
    static func expand(_ text: String) -> String {
        var out = text
        let now = Date()

        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        let tf = DateFormatter(); tf.dateStyle = .none; tf.timeStyle = .short
        let dtf = DateFormatter(); dtf.dateStyle = .medium; dtf.timeStyle = .short

        let date = df.string(from: now)
        let time = tf.string(from: now)
        let datetime = dtf.string(from: now)
        let clip = NSPasteboard.general.string(forType: .string) ?? ""

        let map: [String: String] = [
            "{date}": date, ":date:": date,
            "{time}": time, ":time:": time,
            "{datetime}": datetime,
            "{clipboard}": clip, ":clipboard:": clip,
        ]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }
}
