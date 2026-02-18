//
//  PlaybackControlView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/8/25.
//

import SwiftUI

struct PlaybackControlLandscapeView: View {
    @State var mediaManager: MediaManagerVM
    
    var body: some View {
        VStack(spacing: 0) {
            // Guard against invalid range during reload
            if mediaManager.mediaPlayerViewModel.totalFrames > 0 {
                Slider(
                    value: Binding(
                        get: { Double(mediaManager.currentFrameIndex) },
                        set: {
                            let newIndex = Int($0)
                            mediaManager.mediaPlayerViewModel.moveToFrame(newIndex)
                        }
                    ),
                    in: 0...Double(mediaManager.mediaPlayerViewModel.totalFrames - 1),
                    step: 1
                )
                .padding(.horizontal, 8)
            } else {
                // Placeholder to preserve layout during loading
                Slider(value: .constant(0), in: 0...1)
                    .padding(.horizontal, 8)
                    .disabled(true)
            }
            
            // Playback controls
            HStack {
                Button(action: { mediaManager.mediaPlayerViewModel.firstFrame() }) {
                    Image(systemName: "backward.end.fill").font(.body)
                }
                
                Button(action: { mediaManager.mediaPlayerViewModel.previousFrame() }) {
                    Image(systemName: "backward.fill").font(.body)
                }
                
                let totalFrames = mediaManager.mediaPlayerViewModel.totalFrames
                let isDone = totalFrames > 0 && mediaManager.currentFrameIndex == totalFrames - 1
                Button(action: { mediaManager.tooglePlayback() }) {
                    Image(systemName: isDone ? "arrow.counterclockwise" : mediaManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                        .foregroundColor(isDone ? .gray : mediaManager.isPlaying ? .red : .blue)
                }
                .frame(width: 50, height: 50)
                .disabled(totalFrames == 0)
                
                Button(action: { mediaManager.mediaPlayerViewModel.nextFrame() }) {
                    Image(systemName: "forward.fill").font(.body)
                }
                
                Button(action: { mediaManager.mediaPlayerViewModel.lastFrame() }) {
                    Image(systemName: "forward.end.fill").font(.body)
                }
            }
            .disabled(mediaManager.mediaPlayerViewModel.totalFrames == 0)
        }
    }
}

