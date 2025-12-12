//
//  TrackerVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/19/25.
//

// PoseTracker.swift
// Drop-in tracker for gymnast swing tracking.
// Assumes you have a PoseBox type elsewhere with: var bbox: CGRect

import Foundation
import CoreGraphics

// MARK: - Public API State

struct TrackedPose {
    public var id: Int
    public var pose: PoseBox
    public var missedFrames: Int
    public var kalman: KalmanFilter
    public var motionScore: Double            // accumulated displacement magnitude
    public var vyHistory: [Double] = []       // recent vertical velocities
    public var centerHistory: [CGPoint] = []  // recent centers
    public var confirmed: Bool = false        // becomes true after N hits
    public var hits: Int = 0                  // consecutive matched frames
}

var tracks: [TrackedPose] = []
public var nextTrackID: Int = 0

// MARK: - Tunables

fileprivate let BIG: Double = 1e6
fileprivate let MIN_IOU: CGFloat = 0.05
fileprivate let ROI_BONUS: Double = 0.30          // reduce cost if inside ROI
fileprivate let GATE_MAHAL: Double = 9.0          // ~3σ^2 gating ellipse
fileprivate let CONFIRM_HITS: Int = 3
fileprivate let MAX_MISSED: Int = 45              // keep track alive ~1.5s @30fps
fileprivate let VY_WINDOW: Int = 30               // ~1s window
fileprivate let MIN_ENERGY: Double = 5.0
fileprivate let MIN_ZERO_CROSS: Int = 3

// Render policy (used by shouldRender)
public let RENDER_GRACE_MISSED = 1
public let MAX_RENDER_DRIFT: CGFloat = 30

// MARK: - Kalman Filter (constant-velocity)

public final class KalmanFilter {
    // State: [x, y, vx, vy]
    public var x: [Double] = [0, 0, 0, 0]
    public var P: [[Double]] = identity(size: 4)
    public var Q: [[Double]] = { // process noise (tuned)
        let q = 1e-2
        return [[q,0,0,0],
                [0,q,0,0],
                [0,0,q,0],
                [0,0,0,q]]
    }()
    public var R: [[Double]] = { // measurement noise (tuned)
        let r = 1e-1
        return [[r,0],
                [0,r]]
    }()

    public init(x: Double, y: Double) {
        self.x = [x, y, 0, 0]
        self.P = identity(size: 4)
    }

    @discardableResult
    public func predict(dt: Double = 1.0) -> (Double, Double) {
        let F: [[Double]] = [
            [1,0,dt,0],
            [0,1,0,dt],
            [0,0,1,0],
            [0,0,0,1]
        ]
        x = matVecMul(F, x)
        P = matAdd(matMul(F, matMul(P, transpose(F))), Q)
        return (x[0], x[1])
    }

    // Non-mutating peek (useful for cost building without stepping state)
    public func peekPrediction(dt: Double = 1.0) -> (Double, Double, [[Double]]) {
        let F: [[Double]] = [
            [1,0,dt,0],
            [0,1,0,dt],
            [0,0,1,0],
            [0,0,0,1]
        ]
        let xp = matVecMul(F, x)
        let Pp = matAdd(matMul(F, matMul(P, transpose(F))), Q)
        return (xp[0], xp[1], Pp)
    }

    public func update(zx: Double, zy: Double) {
        let z = [zx, zy]
        let H = [[1.0,0,0,0],
                 [0,1.0,0,0]]
        let y = vecSub(z, matVecMul(H, x)) // innovation
        let S = matAdd(matMul(H, matMul(P, transpose(H))), R)
        let SInv = inv2x2(S)
        let K = matMul(matMul(P, transpose(H)), SInv)
        x = vecAdd(x, matVecMul(K, y))
        let I = identity(size: 4)
        let KH = matMul(K, H)
        P = matMul(matSub(I, KH), P)
    }
}

// MARK: - Public tracker update

/// Update global `tracks` with new detections and return the current list.
/// - Parameters:
///   - detections: PoseBox array (must have `bbox: CGRect`)
///   - roi: Optional region of interest (e.g., around the horizontal bar)
/// - Returns: Updated tracks
@discardableResult
func updateTracks(with detections: [PoseBox], roi: CGRect?) -> [TrackedPose] {
    // 1) Predict all existing tracks forward (mutating)
    for i in 0..<tracks.count {
        _ = tracks[i].kalman.predict(dt: 1.0)
    }

    // 2) Build cost matrix (minimize) between tracks and detections
    let cost = buildCostMatrix(tracks: tracks, detections: detections, roi: roi)

    // 3) Solve assignment
    let matches = hungarian(cost)

    var updated: [TrackedPose] = []
    var matchedDets = Set<Int>()
    var matchedTracks = Set<Int>()

    // 4) Apply matches
    for (ti, di) in matches {
        guard ti < tracks.count, di < detections.count else { continue }
        var t = tracks[ti]
        let det = detections[di]
        let c = center(of: det.bbox)

        // Kalman correction
        t.kalman.update(zx: Double(c.x), zy: Double(c.y))

        // Motion accumulation (displacement vs previous corrected center)
        if let last = t.centerHistory.last {
            let dx = Double(c.x - last.x)
            let dy = Double(c.y - last.y)
            t.motionScore += sqrt(dx*dx + dy*dy)
        }

        // Kinematics (vertical velocity & history)
        updateKinematics(&t, newCenter: c)

        // Track bookkeeping
        t.pose = det
        t.missedFrames = 0
        t.hits += 1
        if !t.confirmed, t.hits >= CONFIRM_HITS { t.confirmed = true }

        updated.append(t)
        matchedDets.insert(di)
        matchedTracks.insert(ti)
    }

    // 5) Unmatched tracks: keep alive (no pose update for rendering)
    for (i, var t) in tracks.enumerated() where !matchedTracks.contains(i) {
        t.missedFrames += 1
        if t.missedFrames < MAX_MISSED {
            updated.append(t)
        }
    }

    // 6) New detections -> new tracks
    for (i, det) in detections.enumerated() where !matchedDets.contains(i) {
        let c = center(of: det.bbox)
        let kf = KalmanFilter(x: Double(c.x), y: Double(c.y))
        let nt = TrackedPose(
            id: nextTrackID,
            pose: det,
            missedFrames: 0,
            kalman: kf,
            motionScore: 0.0,
            vyHistory: [],
            centerHistory: [c],
            confirmed: false,
            hits: 1
        )
        nextTrackID += 1
        updated.append(nt)
    }

    tracks = updated
    return tracks
}

// MARK: - Selection helpers

/// Pick the gymnast likely doing a swing: prefer inside ROI, then highest swing score.
func pickSwinger(from tracks: [TrackedPose], roi: CGRect?) -> TrackedPose? {
    guard !tracks.isEmpty else { return nil }
    let sorted = tracks.sorted { a, b in
        let aIn = insideROI(center(of: a.pose.bbox), roi)
        let bIn = insideROI(center(of: b.pose.bbox), roi)
        if aIn != bIn { return aIn && !bIn }
        return swingScore(a) > swingScore(b)
    }
    return sorted.first
}

/// Render policy: only draw if recently observed and drift is small.
func shouldRender(_ t: TrackedPose) -> Bool {
    if t.missedFrames == 0 { return true }
    if t.missedFrames > RENDER_GRACE_MISSED { return false }
    guard let last = t.centerHistory.last else { return false }
    let (px, py, _) = t.kalman.peekPrediction(dt: 1.0)
    let dx = CGFloat(px) - last.x
    let dy = CGFloat(py) - last.y
    let drift = sqrt(dx*dx + dy*dy)
    return drift <= MAX_RENDER_DRIFT
}

// MARK: - Cost Matrix (IoU + Mahalanobis gating + ROI bonus)

fileprivate func buildCostMatrix(tracks: [TrackedPose], detections: [PoseBox], roi: CGRect?) -> [[Double]] {
    let n = tracks.count
    let m = detections.count
    if n == 0 || m == 0 { return [] }

    var cost: [[Double]] = Array(repeating: Array(repeating: BIG, count: m), count: n)

    for (ti, t) in tracks.enumerated() {
        let (px, py, Pp) = t.kalman.peekPrediction(dt: 1.0)
        let pw = Double(t.pose.bbox.width)
        let ph = Double(t.pose.bbox.height)
        let predictedBBox = CGRect(
            x: CGFloat(px - pw/2.0),
            y: CGFloat(py - ph/2.0),
            width: CGFloat(pw),
            height: CGFloat(ph)
        )

        for (di, det) in detections.enumerated() {
            let iouVal = iou(predictedBBox, det.bbox)
            if iouVal < MIN_IOU { continue } // remain BIG (invalid)

            let c = center(of: det.bbox)
            let m2 = mahalanobis2(pred:(px,py), cov:Pp, point:(Double(c.x), Double(c.y)))
            if m2 > GATE_MAHAL { continue }   // remain BIG

            var cst = 1.0 - Double(iouVal)
            if insideROI(c, roi) { cst = max(0.0, cst - ROI_BONUS) }
            cost[ti][di] = cst
        }
    }
    return cost
}

// MARK: - Swing scoring

fileprivate func updateKinematics(_ t: inout TrackedPose, newCenter: CGPoint) {
    if let last = t.centerHistory.last {
        let vy = Double(newCenter.y - last.y)
        t.vyHistory.append(vy)
        if t.vyHistory.count > VY_WINDOW { t.vyHistory.removeFirst() }
    }
    t.centerHistory.append(newCenter)
    if t.centerHistory.count > VY_WINDOW { t.centerHistory.removeFirst() }
}

fileprivate func swingScore(_ t: TrackedPose) -> Double {
    guard !t.vyHistory.isEmpty else { return 0 }
    let energy = t.vyHistory.reduce(0.0) { $0 + $1*$1 } / Double(t.vyHistory.count)
    var zeros = 0
    for i in 1..<t.vyHistory.count {
        let a = t.vyHistory[i-1], b = t.vyHistory[i]
        if (a <= 0 && b > 0) || (a >= 0 && b < 0) { zeros += 1 }
    }
    if energy < MIN_ENERGY || zeros < MIN_ZERO_CROSS { return 0 }
    return energy + Double(zeros)
}

// MARK: - Geometry helpers

public func center(of rect: CGRect) -> CGPoint {
    CGPoint(x: rect.midX, y: rect.midY)
}

public func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let inter = a.intersection(b)
    if inter.isNull || inter.isEmpty { return 0 }
    let interArea = inter.width * inter.height
    let unionArea = a.width * a.height + b.width * b.height - interArea
    return unionArea > 0 ? interArea / unionArea : 0
}

fileprivate func insideROI(_ pt: CGPoint, _ roi: CGRect?) -> Bool {
    guard let roi = roi else { return false }
    return roi.contains(pt)
}

// MARK: - Hungarian (robust padded min-cost)

fileprivate func hungarian(_ cost: [[Double]]) -> [(track: Int, det: Int)] {
    let n = cost.count
    let m = cost.first?.count ?? 0
    if n == 0 || m == 0 { return [] }

    let dim = max(n, m)
    // Build square with BIG padding so dummies never chosen unless needed
    var C = Array(repeating: Array(repeating: BIG, count: dim), count: dim)
    for i in 0..<n {
        for j in 0..<m { C[i][j] = cost[i][j] }
    }

    var u = Array(repeating: 0.0, count: dim+1)
    var v = Array(repeating: 0.0, count: dim+1)
    var p = Array(repeating: 0,    count: dim+1)
    var way = Array(repeating: 0,  count: dim+1)

    for i in 1...dim {
        p[0] = i
        var j0 = 0
        var minv = Array(repeating: Double.greatestFiniteMagnitude, count: dim+1)
        var used = Array(repeating: false, count: dim+1)
        repeat {
            used[j0] = true
            let i0 = p[j0]
            var delta = Double.greatestFiniteMagnitude
            var j1 = 0
            for j in 1...dim where !used[j] {
                let cur = C[i0-1][j-1] - u[i0] - v[j]
                if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                if minv[j] < delta { delta = minv[j]; j1 = j }
            }
            for j in 0...dim {
                if used[j] { u[p[j]] += delta; v[j] -= delta }
                else { minv[j] -= delta }
            }
            j0 = j1
        } while p[j0] != 0
        repeat {
            let j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
        } while j0 != 0
    }

    var assignment: [(Int, Int)] = []
    for j in 1...dim {
        let i = p[j]
        if i == 0 { continue }
        if i <= n && j <= m && C[i-1][j-1] < BIG {
            assignment.append((i-1, j-1))
        }
    }
    return assignment
}

// MARK: - Linear algebra helpers

fileprivate func matMul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    let m = A.count
    let n = B[0].count
    let p = B.count
    var R = Array(repeating: Array(repeating: 0.0, count: n), count: m)
    for i in 0..<m {
        for j in 0..<n {
            var s = 0.0
            for k in 0..<p { s += A[i][k] * B[k][j] }
            R[i][j] = s
        }
    }
    return R
}

fileprivate func matVecMul(_ A: [[Double]], _ x: [Double]) -> [Double] {
    let m = A.count
    let n = x.count
    var y = Array(repeating: 0.0, count: m)
    for i in 0..<m {
        var s = 0.0
        for j in 0..<n { s += A[i][j] * x[j] }
        y[i] = s
    }
    return y
}

fileprivate func transpose(_ A: [[Double]]) -> [[Double]] {
    let m = A.count
    let n = A[0].count
    var R = Array(repeating: Array(repeating: 0.0, count: m), count: n)
    for i in 0..<m { for j in 0..<n { R[j][i] = A[i][j] } }
    return R
}

fileprivate func matAdd(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    var R = A
    for i in 0..<A.count {
        for j in 0..<A[0].count { R[i][j] += B[i][j] }
    }
    return R
}

fileprivate func matSub(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    var R = A
    for i in 0..<A.count {
        for j in 0..<A[0].count { R[i][j] -= B[i][j] }
    }
    return R
}

fileprivate func vecAdd(_ a: [Double], _ b: [Double]) -> [Double] {
    zip(a, b).map(+)
}

fileprivate func vecSub(_ a: [Double], _ b: [Double]) -> [Double] {
    zip(a, b).map(-)
}

fileprivate func identity(size: Int) -> [[Double]] {
    var I = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    for i in 0..<size { I[i][i] = 1.0 }
    return I
}

// Inverse of a 2x2 matrix
fileprivate func inv2x2(_ M: [[Double]]) -> [[Double]] {
    let a = M[0][0], b = M[0][1], c = M[1][0], d = M[1][1]
    let det = a*d - b*c
    if det == 0 { return [[0,0],[0,0]] }
    let inv = 1.0 / det
    return [[ d*inv, -b*inv],
            [-c*inv,  a*inv]]
}

// Mahalanobis distance squared using 2x2 position covariance
fileprivate func mahalanobis2(pred: (Double,Double), cov: [[Double]], point: (Double,Double)) -> Double {
    let S = [[cov[0][0], cov[0][1]],
             [cov[1][0], cov[1][1]]]
    let invS = inv2x2(S)
    let dx = point.0 - pred.0
    let dy = point.1 - pred.1
    let v = [[dx],[dy]]
    let t = matMul(transpose(v), matMul(invS, v))
    return t[0][0]
}
