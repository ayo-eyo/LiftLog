import SwiftUI

struct RestTimerView: View {
    let restTimer: RestTimer
    let duration: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = restTimer.remaining(at: timeline.date)
            let progress = duration > 0 ? remaining / duration : 0

            ZStack {
                Circle().stroke(.hairline, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.plateBlue, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Text(remaining.clockString)
                    .font(.mono(22))
                    .foregroundStyle(.ink)
            }
            .frame(width: 88, height: 88)
        }
    }
}
