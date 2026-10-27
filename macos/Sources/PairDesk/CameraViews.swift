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

struct CameraGalleryView: View {
    @ObservedObject var rtc: RTCService

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Camera view").font(.title2.bold())
                    Text("Live video from people on this call")
                        .font(.callout).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Text("\(rtc.cameraFeeds.count) \(rtc.cameraFeeds.count == 1 ? "camera" : "cameras")")
                    .font(.callout.monospacedDigit()).foregroundStyle(Theme.textMuted)
            }

            if rtc.cameraFeeds.isEmpty {
                ContentUnavailableView("No cameras are on", systemImage: "video.slash",
                                       description: Text("Turn on a camera from the call controls to show video here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(rtc.cameraFeeds) { feed in
                            CameraGalleryCard(feed: feed).id(ObjectIdentifier(feed.track))
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(22)
        .background(Theme.surface)
        .frame(minWidth: 700, minHeight: 480)
    }
}

private struct CameraGalleryCard: View {
    let feed: CameraFeed

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                Color.black
                SwiftUIVideoView(feed.track,
                                 layoutMode: .fill,
                                 mirrorMode: feed.isLocal ? .mirror : .off)
                LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
                Label(feed.isLocal ? "\(feed.name) · You" : feed.name,
                      systemImage: feed.isLocal ? "person.crop.rectangle" : "person.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera from \(feed.name)\(feed.isLocal ? ", you" : "")")
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
