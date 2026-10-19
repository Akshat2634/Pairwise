import SwiftUI
@preconcurrency import LiveKit

struct CameraStrip: View {
    let feeds: [CameraFeed]

    var body: some View {
        if !feeds.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(feeds) { feed in
                        CameraFeedTile(feed: feed).id(ObjectIdentifier(feed.track))
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 108)
            .accessibilityLabel("Camera video from people on this call")
        }
    }
}

private struct CameraFeedTile: View {
    let feed: CameraFeed
    @StateObject private var observer: TrackDelegateObserver

    init(feed: CameraFeed) {
        self.feed = feed
        _observer = StateObject(wrappedValue: TrackDelegateObserver(track: feed.track))
    }

    private var metrics: CameraVideoMetrics {
        guard let statistics = observer.statistics else { return CameraVideoMetrics() }
        if feed.isLocal {
            let video = statistics.outboundRtpStream.first(where: { $0.kind == "video" })
                ?? statistics.outboundRtpStream.first
            return CameraVideoMetrics(width: video?.frameWidth, height: video?.frameHeight,
                                      framesPerSecond: video?.framesPerSecond)
        }
        let video = statistics.inboundRtpStream.first(where: { $0.kind == "video" })
            ?? statistics.inboundRtpStream.first
        return CameraVideoMetrics(width: video?.frameWidth, height: video?.frameHeight,
                                  framesPerSecond: video?.framesPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SwiftUIVideoView(feed.track,
                             layoutMode: .fill,
                             mirrorMode: feed.isLocal ? .mirror : .off)
                .frame(width: 112, height: 68)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(feed.isLocal ? "\(feed.name) · You" : feed.name)
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)
            Text(metrics.summary)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)
                .accessibilityLabel("Camera video quality: \(metrics.summary)")
        }
        .help("\(feed.isLocal ? "Your camera" : "\(feed.name)'s camera") · \(metrics.summary)")
    }
}
