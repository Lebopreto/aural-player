import AVFoundation

typealias SessionCompletionHandler = (PlaybackSession) -> Void

/*
    A custom AVAudioPlayerNode that provides:
 
    1 - Convenient scheduling functions that convert seek times to audio frame positions. Callers can schedule segments
    in terms of seek times and do not need to compute segments in terms of audio frames.
 
    2 - Computation of the current track seek position (by converting playerNode's sampleTime).
 */
class AuralPlayerNode: AVAudioPlayerNode {

    // This property will have no effect on macOS 10.12 or older systems.
    var completionCallbackType: AVAudioPlayerNodeCompletionCallbackType = .dataPlayedBack
    
    var completionCallbackQueue: DispatchQueue = DispatchQueue.global(qos: .userInteractive)
    
    // The start frame for the current playback session (used to calculate seek position). Represents the point in the track at which playback began.
    var startFrame: AVAudioFramePosition = 0

    // Cached seek position (used when looping, to remember last seek position and avoid displaying 0 when player is temporarily stopped at the end of a loop)
    var cachedSeekPosn: Double = 0
    
    // The absolute minimum frame count when scheduling a segment (to prevent crashes in the playerNode).
    static let minFrames: AVAudioFrameCount = 1
    
    // This flag determines whether the legacy scheduling API should be used (i.e. <= macOS 10.12)
    // If false, the newer APIs will be used.
    var useLegacyAPI: Bool
    
    init(useLegacyAPI: Bool) {
        self.useLegacyAPI = useLegacyAPI
    }
    
    // Retrieves the current seek position, in seconds
    var seekPosition: Double {
        
        if let nodeTime = lastRenderTime, let playerTime = playerTime(forNodeTime: nodeTime) {
            cachedSeekPosn = Double(startFrame + playerTime.sampleTime) / playerTime.sampleRate
        }

        // Default to last remembered position when nodeTime is nil
        return cachedSeekPosn
    }
    
    func scheduleSegment(_ session: PlaybackSession, _ completionHandler: @escaping SessionCompletionHandler, _ startTime: Double, _ endTime: Double? = nil, _ startFrame: AVAudioFramePosition? = nil, _ immediatePlayback: Bool = true) -> PlaybackSegment? {

        guard let segment = computeSegment(session, startTime, endTime, startFrame) else {return nil}
        
        scheduleSegment(segment, completionHandler, immediatePlayback)
        return segment
    }

    func scheduleSegment(_ segment: PlaybackSegment, _ completionHandler: @escaping SessionCompletionHandler, _ immediatePlayback: Bool = true) {

        // The start frame and seek position should be reset only if this segment will be played immediately.
        // If it is being scheduled for the future, doing this will cause inaccurate seek position values.
        if immediatePlayback {
            
            // Advance the last seek position to the new position
            startFrame = segment.firstFrame
            cachedSeekPosn = segment.startTime
        }
        
        if #available(OSX 10.13, *), !useLegacyAPI {
            
            scheduleSegment(segment.playingFile, startingFrame: segment.firstFrame, frameCount: segment.frameCount, at: nil, completionCallbackType: completionCallbackType, completionHandler: {(callbackType: AVAudioPlayerNodeCompletionCallbackType) -> Void in
                self.completionCallbackQueue.async {completionHandler(segment.session)}
            })

        } else {
            
            scheduleSegment(segment.playingFile, startingFrame: segment.firstFrame, frameCount: segment.frameCount, at: nil, completionHandler: {() -> Void in
                self.completionCallbackQueue.async {completionHandler(segment.session)}
            })
        }
    }
    
    private func areStartAndEndTimeValid(_ startTime: Double, _ endTime: Double?) -> Bool {
        
        if let theEndTime = endTime {
            return startTime >= 0 && theEndTime >= 0 && startTime <= theEndTime
        }
        
        return startTime >= 0
    }
    
    // Computes an audio file segment. Given seek times, computes the corresponding audio frames.
    func computeSegment(_ session: PlaybackSession, _ startTime: Double, _ endTime: Double? = nil, _ startFrame: AVAudioFramePosition? = nil) -> PlaybackSegment? {
        
        guard let playbackInfo = session.track.playbackInfo, let playingFile: AVAudioFile = playbackInfo.audioFile,
            areStartAndEndTimeValid(startTime, endTime) else {
            return nil
        }

        let sampleRate = playbackInfo.sampleRate
        let lastFrameInFile: AVAudioFramePosition = playbackInfo.frames - 1

        // If an exact start frame is specified, use it.
        // Otherwise, multiply sample rate by the new seek time in seconds to obtain the start frame.
        var firstFrame: AVAudioFramePosition = startFrame ?? AVAudioFramePosition.fromTrackTime(startTime, sampleRate)
        
        var lastFrame: AVAudioFramePosition
        var segmentEndTime: Double

        // Check if end time is specified.
        if let theEndTime = endTime {

            // Use loop end time to calculate the last frame. Ensure the last frame doesn't go past the actual last frame in the file. Rounding may cause this problem.
            lastFrame = min(AVAudioFramePosition.fromTrackTime(theEndTime, sampleRate), lastFrameInFile)
            segmentEndTime = theEndTime

        } else {

            // No end time specified, use audio file's total frame count to determine the last frame
            lastFrame = lastFrameInFile
            segmentEndTime = session.track.duration
        }
        
        // NOTE - Assign to a signed Int value here to account for possible negative values
        var frameCount: Int64 = lastFrame - firstFrame + 1

        // If the frame count is less than the minimum required to continue playback,
        // schedule the minimum frame count for playback, to avoid crashes in the playerNode.
        if frameCount < AuralPlayerNode.minFrames {
            
            frameCount = Int64(AuralPlayerNode.minFrames)
            firstFrame = lastFrame - frameCount + 1
        }
        
        // If startFrame is specified, use it to calculate a precise start time.
        let segmentStartTime: Double = startFrame == nil ? startTime : startFrame!.toTrackTime(sampleRate)
        
        return PlaybackSegment(session, playingFile, firstFrame, lastFrame, AVAudioFrameCount(frameCount), segmentStartTime, segmentEndTime)
    }
}
