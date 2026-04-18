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
            // Frame Slider
            Slider(
                value: Binding(
                    get: { Double(mediaManager.currentFrameIndex) },
                    set: {
                        let newIndex = Int($0)
                        // First set the frame directly - this is the key fix
                        mediaManager.mediaPlayerVM.moveToFrame(newIndex)
                    }
                ),
                in: 0...Double(mediaManager.mediaPlayerVM.totalFrames - 1),
                step: 1
            )
            .padding(.horizontal, 8)
            
            // Playback controls
            HStack {
                // Back to start button
                Button(action: {
                    mediaManager.mediaPlayerVM.firstFrame()
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.body)
                }
                
                // Previous frame button
                Button(action: {
                    mediaManager.mediaPlayerVM.previousFrame()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }
                
                // REWORK >> Play/Pause/Reset button
                let isDone = mediaManager.currentFrameIndex == mediaManager.mediaPlayerVM.totalFrames - 1
                Button(action: {
                    mediaManager.tooglePlayback()
                }) {
                    Image(systemName: isDone ? "arrow.counterclockwise" : mediaManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                        .foregroundColor(isDone ? .gray : mediaManager.isPlaying ? .red : .blue)
                }
                .frame(width: 50, height: 50)
                
                // Next frame button
                Button(action: {
                    mediaManager.mediaPlayerVM.nextFrame()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
                
                // Forward to end button
                Button(action: {
                    mediaManager.mediaPlayerVM.lastFrame()
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                }
            }
        }
    }
}


