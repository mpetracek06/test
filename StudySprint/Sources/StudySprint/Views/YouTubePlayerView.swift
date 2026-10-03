import SwiftUI
import WebKit
import StudySprintCore

/// Plays a YouTube video inside the app, jumping straight to the segment that matters
/// at the suggested speed (via the YouTube IFrame Player API).
struct YouTubePlayerView: NSViewRepresentable {
    let video: VideoResource
    var speed: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        load(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedVideoID != video.id {
            load(into: webView, coordinator: context.coordinator)
        } else if context.coordinator.speed != speed {
            context.coordinator.speed = speed
            webView.evaluateJavaScript("window.setSpeed && window.setSpeed(\(speed))")
        }
    }

    private func load(into webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedVideoID = video.id
        coordinator.speed = speed
        guard let id = video.youTubeID else { return }
        webView.loadHTMLString(Self.html(videoID: id, start: video.startSeconds, end: video.endSeconds, speed: speed),
                               baseURL: URL(string: "https://studysprint.app/"))
    }

    final class Coordinator {
        weak var webView: WKWebView?
        var loadedVideoID: UUID?
        var speed: Double = 1
    }

    static func html(videoID: String, start: Int, end: Int, speed: Double) -> String {
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let endVar = end > 0 ? ", end: \(end)" : ""
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player, wanted = \(speed);
          window.setSpeed = function(s) { wanted = s; if (player && player.setPlaybackRate) player.setPlaybackRate(s); };
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '\(safeID)',
              playerVars: { start: \(max(0, start))\(endVar), autoplay: 1, rel: 0, modestbranding: 1, playsinline: 1,
                            origin: 'https://studysprint.app' },
              events: {
                onReady: function(e) { e.target.setPlaybackRate(wanted); e.target.playVideo(); },
                onStateChange: function(e) {
                  if (e.data === YT.PlayerState.PLAYING && e.target.getPlaybackRate() !== wanted) e.target.setPlaybackRate(wanted);
                }
              }
            });
          }
        </script>
        </body></html>
        """
    }
}
