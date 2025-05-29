//
//  PlaybackControlView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct PlaybackControlView: View {
    @ObservedObject var cameraManager: CameraLiDARManager
    let totalFrames: Int
    @State private var isPlaying = false
    @State private var isFinished = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Frame counter
            Text("Frame \(cameraManager.currentFrameIndex + 1)/\(totalFrames)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Playback controls
            HStack {
                // Back to start button
                Button(action: {
                    moveToFirstFrame()
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                
                // Previous frame button
                Button(action: {
                    moveToPreviousFrame()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                
                // REWORK >> Play/Pause/Reset button
                // TODO: Bug when slider is used after video stopped, the button still "pause" because isPlaying is not updated here
                Button(action: {
                    cameraManager.currentFrameIndex + 1 == totalFrames ? resetPlayback() : togglePlayback()
                }) {
                    Image(systemName: cameraManager.currentFrameIndex + 1 == totalFrames ? "arrow.counterclockwise": (isPlaying ? "pause.fill" : "play.fill"))
                        .font(.title)
                        .foregroundColor(cameraManager.currentFrameIndex + 1 == totalFrames ? .gray : (isPlaying ? .red : .blue))
                }
                .frame(width: 50, height: 50)
                
                // Next frame button
                Button(action: {
                    moveToNextFrame()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                
                // Forward to end button
                Button(action: {
                    moveToLastFrame()
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                }
            }
            
            // Frame slider
            // Frame slider
            Slider(
                value: Binding(
                    get: { Double(cameraManager.currentFrameIndex) },
                    set: {
                        let newIndex = Int($0)
                        // First set the frame directly - this is the key fix
                        cameraManager.setFrame(to: newIndex)
                        // Then notify about the change
                        notifyFrameChanged(newIndex)
                    }
                ),
                in: 0...Double(totalFrames - 1),
                step: 1
            )
            .padding(.horizontal)
        }
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        
        if isPlaying {
            cameraManager.startPlayback()
        } else {
            cameraManager.stopPlayback()
        }
    }
    
    private func resetPlayback() {
        isPlaying = false // Reset isPlaying
        
        cameraManager.stopPlayback()
        cameraManager.currentFrameIndex = 0
        notifyFrameChanged(0)
    }
    
    // IMPROVED FRAME NAVIGATION WITH NOTIFICATION
    private func moveToFirstFrame() {
        print("⏮️ Moving to first frame")
        cameraManager.setFrame(to: 0)
        notifyFrameChanged(0)
    }

    private func moveToPreviousFrame() {
        if cameraManager.currentFrameIndex > 0 {
            let newIndex = cameraManager.currentFrameIndex - 1
            print("◀️ Moving to previous frame: \(newIndex)")
            cameraManager.setFrame(to: newIndex)
            notifyFrameChanged(newIndex)
        }
    }

    private func moveToNextFrame() {
        if cameraManager.currentFrameIndex < totalFrames - 1 {
            let newIndex = cameraManager.currentFrameIndex + 1
            print("▶️ Moving to next frame: \(newIndex)")
            cameraManager.setFrame(to: newIndex)
            notifyFrameChanged(newIndex)
        }
    }

    private func moveToLastFrame() {
        let lastIndex = totalFrames - 1
        print("⏭️ Moving to last frame: \(lastIndex)")
        cameraManager.setFrame(to: lastIndex)
        notifyFrameChanged(lastIndex)
    }
    
    // Function to send notification about frame change
    private func notifyFrameChanged(_ frameIndex: Int) {
        // Post notification for frame change
        NotificationCenter.default.post(
            name: NSNotification.Name("FrameChanged"),
            object: nil,
            userInfo: ["frameIndex": frameIndex]
        )
    }
}
