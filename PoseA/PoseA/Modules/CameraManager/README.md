# Camera Manager Documentation

## Overview

The refactored camera manager provides a clean, configurable interface for camera operations with automatic LiDAR detection and fallback to basic camera functionality. The architecture is designed to be modular, maintainable, and easy to use.

## Architecture

### Core Components

1. **CameraConfiguration** - Configuration struct that defines camera settings
2. **CameraLiDARManager** - Main camera manager class that handles high-level operations
3. **CameraControllerUI** - Low-level camera controller that manages AVFoundation sessions

### Key Features

- ✅ **Configurable Resolution** - Support for 720p, 1080p, and 4K resolutions
- ✅ **Automatic LiDAR Detection** - Automatically detects LiDAR support and falls back gracefully
- ✅ **Clean Separation of Concerns** - Clear separation between configuration, management, and control
- ✅ **Thread-Safe Operations** - All camera operations are properly queued
- ✅ **Reactive Updates** - Uses Combine for reactive state management
- ✅ **Backward Compatibility** - Maintains compatibility with existing code

## Configuration

### CameraConfiguration

```swift
struct CameraConfiguration {
    enum Resolution: CaseIterable {
        case hd720p    // 1280x720
        case hd1080p   // 1920x1080
        case hd4k       // 3840x2160
    }
    
    let resolution: Resolution
    let enableLiDAR: Bool
    let enableDepthFiltering: Bool
    let cameraPosition: AVCaptureDevice.Position
}
```

### Default Configuration

```swift
let defaultConfig = CameraConfiguration(
    resolution: .hd1080p,
    enableLiDAR: true,
    enableDepthFiltering: true,
    cameraPosition: .back
)
```

## Usage Examples

### Basic Setup

```swift
// Create with default configuration
let cameraManager = CameraLiDARManager()

// Or with custom configuration
let config = CameraConfiguration(
    resolution: .hd4k,
    enableLiDAR: true,
    enableDepthFiltering: true,
    cameraPosition: .back
)
let cameraManager = CameraLiDARManager(configuration: config)
```

### Dynamic Configuration Updates

```swift
// Update resolution
cameraManager.updateResolution(.hd4k)

// Toggle LiDAR (only if supported)
cameraManager.toggleLiDAR()

// Toggle depth filtering
cameraManager.toggleDepthFiltering()
```

### Camera Control

```swift
// Start/stop stream
cameraManager.startStream()
cameraManager.pauseStream()
cameraManager.resumeStream()

// Set fixed focus
cameraManager.setFixedFocus()

// Depth detection
cameraManager.startCenterDepthDetection()
cameraManager.stopCenterDepthDetection()
```

### SwiftUI Integration

```swift
struct CameraView: View {
    @StateObject private var cameraManager = CameraLiDARManager()
    
    var body: some View {
        VStack {
            // Camera status
            Text("LiDAR: \(cameraManager.isLiDARSupported ? "Supported" : "Not Supported")")
            Text("Resolution: \(cameraManager.cameraConfiguration.resolution.description)")
            
            // Controls
            Button("Toggle LiDAR") {
                cameraManager.toggleLiDAR()
            }
            .disabled(!cameraManager.isLiDARSupported)
            
            // Depth display
            if let depth = cameraManager.centerDepthValue {
                Text("Depth: \(depth, specifier: "%.3f")m")
            }
        }
    }
}
```

## LiDAR Detection and Fallback

The camera manager automatically:

1. **Detects LiDAR Support** - Checks if the device has LiDAR capabilities
2. **Configures Appropriately** - Sets up LiDAR or basic camera based on configuration
3. **Graceful Fallback** - Falls back to basic camera if LiDAR setup fails
4. **State Management** - Maintains clear state about LiDAR support and usage

### LiDAR Support Check

```swift
// Check if LiDAR is supported
if cameraManager.isLiDARSupported {
    // Device has LiDAR
} else {
    // Device doesn't have LiDAR
}

// Check if LiDAR is currently enabled
if cameraManager.isLiDAREnabled {
    // LiDAR is active
} else {
    // Basic camera is active
}
```

## Resolution Management

### Available Resolutions

- **720p HD** (1280x720) - Good for performance
- **1080p Full HD** (1920x1080) - Balanced quality/performance
- **4K Ultra HD** (3840x2160) - Maximum quality

### Resolution Selection

The system automatically selects the best available format that meets or exceeds the requested resolution:

```swift
// Request 4K resolution
cameraManager.updateResolution(.hd4k)

// The system will:
// 1. Find the best format >= 3840x2160
// 2. Configure the camera with that format
// 3. Update the configuration state
```

## Thread Safety

All camera operations are properly queued:

- **Session Operations** - Run on dedicated session queue
- **UI Updates** - Always on main thread
- **Data Processing** - On appropriate background queues

## Error Handling

The camera manager provides robust error handling:

```swift
// Configuration errors are handled gracefully
do {
    try cameraManager.controller.configureSession(...)
} catch {
    // Fallback to basic camera
    cameraManager.fallbackToBasicCamera()
}
```

## Performance Considerations

### Resolution Impact

- **720p** - Best performance, lower quality
- **1080p** - Balanced performance and quality
- **4K** - Highest quality, may impact performance

### LiDAR Impact

- **With LiDAR** - Additional depth processing overhead
- **Without LiDAR** - Standard camera performance

### Recommendations

- Use **720p** for real-time processing
- Use **1080p** for general use
- Use **4K** for high-quality recording
- Disable LiDAR if depth data isn't needed

## Migration Guide

### From Old Implementation

1. **Replace direct initialization**:
   ```swift
   // Old
   let cameraManager = CameraLiDARManager()
   
   // New
   let cameraManager = CameraLiDARManager(configuration: CameraConfiguration())
   ```

2. **Update resolution handling**:
   ```swift
   // Old - hardcoded 1920 resolution
   // New - configurable resolution
   cameraManager.updateResolution(.hd4k)
   ```

3. **Use new LiDAR state properties**:
   ```swift
   // Old
   if cameraManager.useLiDAR { ... }
   
   // New
   if cameraManager.isLiDAREnabled { ... }
   ```

## Troubleshooting

### Common Issues

1. **LiDAR not working**:
   - Check `isLiDARSupported` property
   - Verify device has LiDAR hardware
   - Check camera permissions

2. **Resolution not applying**:
   - Verify device supports requested resolution
   - Check for format compatibility
   - Review console logs for format selection

3. **Performance issues**:
   - Try lower resolution (720p)
   - Disable LiDAR if not needed
   - Check for background processing

### Debug Information

Enable logging to see detailed camera setup information:

```swift
// Check camera state
print("LiDAR Supported: \(cameraManager.isLiDARSupported)")
print("LiDAR Enabled: \(cameraManager.isLiDAREnabled)")
print("Resolution: \(cameraManager.cameraConfiguration.resolution.description)")
print("Live Capture: \(cameraManager.isLiveCapture)")
```

## API Reference

### CameraLiDARManager Properties

- `@Published var cameraConfiguration: CameraConfiguration`
- `@Published var isLiDARSupported: Bool`
- `@Published var isLiDAREnabled: Bool`
- `@Published var isLiveCapture: Bool`
- `@Published var centerDepthValue: Float?`

### CameraLiDARManager Methods

- `updateResolution(_:)`
- `toggleLiDAR()`
- `toggleDepthFiltering()`
- `startStream()`
- `pauseStream()`
- `resumeStream()`
- `setFixedFocus()`
- `startCenterDepthDetection()`
- `stopCenterDepthDetection()`

### CameraConfiguration Properties

- `resolution: Resolution`
- `enableLiDAR: Bool`
- `enableDepthFiltering: Bool`
- `cameraPosition: AVCaptureDevice.Position` 