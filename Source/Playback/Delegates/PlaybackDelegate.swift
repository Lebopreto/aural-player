import Foundation

// A function that produces an optional Track (used when deciding which track will play next)
typealias TrackProducer = () -> Track?

class PlaybackDelegate: PlaybackDelegateProtocol, PlaylistChangeListenerProtocol, AsyncMessageSubscriber, MessageSubscriber, ActionMessageSubscriber {
    
    // The actual player
    let player: PlayerProtocol
    
    // The playback sequence
    let sequencer: SequencerProtocol
    
    // User preferences
    let preferences: PlaybackPreferences
    
    // Playback settings per track
    let profiles: PlaybackProfiles
    
    // "Chain of responsibility" chains that are used to perform a sequence of actions when changing tracks
    let startPlaybackChain: StartPlaybackChain
    let stopPlaybackChain: StopPlaybackChain
    let trackPlaybackCompletedChain: TrackPlaybackCompletedChain
    
    init(_ player: PlayerProtocol, _ sequencer: SequencerProtocol, _ profiles: PlaybackProfiles, _ preferences: PlaybackPreferences,
         _ startPlaybackChain: StartPlaybackChain, _ stopPlaybackChain: StopPlaybackChain, _ trackPlaybackCompletedChain: TrackPlaybackCompletedChain) {
        
        self.player = player
        self.sequencer = sequencer
        self.preferences = preferences
        self.profiles = profiles
        
        self.startPlaybackChain = startPlaybackChain
        self.stopPlaybackChain = stopPlaybackChain
        self.trackPlaybackCompletedChain = trackPlaybackCompletedChain
        
        // Subscribe to message notifications
        SyncMessenger.subscribe(messageTypes: [.appExitRequest], subscriber: self)
        SyncMessenger.subscribe(actionTypes: [.savePlaybackProfile, .deletePlaybackProfile], subscriber: self)
        AsyncMessenger.subscribe([.playbackCompleted], subscriber: self, dispatchQueue: DispatchQueue.main)
    }
    
    let subscriberId: String = "PlaybackDelegate"
    
    // MARK: play()
    
    func togglePlayPause() {
        
        // Determine current state of player, to then toggle it
        switch state {
            
        case .noTrack:
            
            beginPlayback()
            
        case .paused:
            
            resume()
            
        case .playing:
            
            pause()
            
        case .waiting:
            
            // Skip gap and start playback
            if let track = waitingTrack {
                playImmediately(track)
            }
            
        case .transcoding:
            
            // Do nothing if transcoding
            return
        }
    }
    
    private func beginPlayback() {
        doPlay({return sequencer.begin()}, PlaybackParams.defaultParams())
    }
    
    private func playImmediately(_ track: Track) {
        doPlay({return track}, PlaybackParams().withAllowDelay(false))
    }
    
    func previousTrack() {
        
        if state != .noTrack {
            doPlay({return sequencer.previous()})
        }
    }
    
    func nextTrack() {
        
        if state != .noTrack {
            doPlay({return sequencer.next()})
        }
    }
    
    func play(_ index: Int, _ params: PlaybackParams) {
        doPlay({return sequencer.select(index)}, params)
    }
    
    func play(_ track: Track, _ params: PlaybackParams) {
        doPlay({return sequencer.select(track)}, params)
    }
    
    func play(_ group: Group, _ params: PlaybackParams) {
        doPlay({return sequencer.select(group)}, params)
    }
    
    // Captures the current player state and proceeds with playback according to the playback sequence
    func doPlay(_ trackProducer: TrackProducer, _ params: PlaybackParams = PlaybackParams.defaultParams()) {
        
        let trackBeforeChange = currentTrack
        let stateBeforeChange = state
        let seekPositionBeforeChange = seekPosition.timeElapsed
        
        let okToPlay = params.interruptPlayback || trackBeforeChange == nil
            
        if okToPlay, let newTrack = trackProducer() {
            
            let requestContext = PlaybackRequestContext(stateBeforeChange, trackBeforeChange, seekPositionBeforeChange, newTrack, params)
            
            startPlaybackChain.execute(requestContext)
        }
    }
    
    func stop() {
        
        let stateBeforeChange = state
        
        if stateBeforeChange != .noTrack {
            
            let trackBeforeChange = currentTrack
            let seekPositionBeforeChange = seekPosition.timeElapsed
            
            let requestContext = PlaybackRequestContext(stateBeforeChange, trackBeforeChange, seekPositionBeforeChange, nil, PlaybackParams.defaultParams())
            stopPlaybackChain.execute(requestContext)
        }
    }
    
    func trackPlaybackCompleted(_ session: PlaybackSession) {
        
        // If the given session has expired, do not continue playback.
        if PlaybackSession.isCurrent(session) {
            trackPlaybackCompleted()
            
        } else {
            
            // If the session has expired, the track completion chain will not execute
            // and the track's profile will not be updated, so ensure that it is.
            // Reset the seek position to 0 since the track completed playback.
            savePlaybackProfileIfNeeded(session.track, 0)
        }
    }
    
    // Continues playback when a track finishes playing.
    func trackPlaybackCompleted() {
        
        let trackBeforeChange = currentTrack
        let stateBeforeChange = state
        let seekPositionBeforeChange = seekPosition.timeElapsed
        
        let requestContext = PlaybackRequestContext(stateBeforeChange, trackBeforeChange, seekPositionBeforeChange, nil, PlaybackParams.defaultParams())
        
        trackPlaybackCompletedChain.execute(requestContext)
    }
    
    // MARK: Other functions
    
    func replay() {
        
        if state.isPlayingOrPaused {
        
            seekToTime(0)
            resumeIfPaused()
        }
    }
    
    private func pause() {
        player.pause()
    }
    
    private func resume() {
        player.resume()
    }
    
    func resumeIfPaused() {
        
        if state == .paused {
            player.resume()
        }
    }
    
    func toggleLoop() -> PlaybackLoop? {
        
        guard state.isPlayingOrPaused else {return nil}
        
        return player.toggleLoop()
    }
    
    // MARK: Seeking functions
    
    func seekBackward(_ actionMode: ActionMode = .discrete) {
        attemptSeek(player.seekPosition - getPrimarySeekLength(actionMode))
    }
    
    func seekBackwardSecondary() {
        attemptSeek(player.seekPosition - secondarySeekLength)
    }
    
    func seekForward(_ actionMode: ActionMode = .discrete) {
        attemptSeek(player.seekPosition + getPrimarySeekLength(actionMode))
    }
    
    func seekForwardSecondary() {
        attemptSeek(player.seekPosition + secondarySeekLength)
    }
    
    // An attempted seek cannot seek outside the bounds of a segment loop (if one is defined).
    // It occurs, for instance, when seeking backward/forward.
    private func attemptSeek(_ seekPosn: Double) {
        
        if state.isPlayingOrPaused, let track = playingTrack {
            
            let seekResult = player.attemptSeekToTime(track, seekPosn)
            
            if seekResult.trackPlaybackCompleted {
                trackPlaybackCompleted()
            }
        }
    }
    
    /*
        Computes the seek length (i.e. interval/adjustment/delta) used as an increment/decrement when performing a "primary" seek, i.e.
        the seeking that can be performed through the player's seek control buttons.
     
        The "actionMode" parameter denotes whether the seeking is occurring in a discrete (using the main controls) or continuous (through a scroll gesture) mode. The amount of seeking performed
        will vary depending on the mode.
     
        TODO: Clarify how useful this actionMode is, and see if it can be eliminated to prevent confusion.
     */
    private func getPrimarySeekLength(_ actionMode: ActionMode) -> Double {
        
        if actionMode == .discrete {
            
            if preferences.primarySeekLengthOption == .constant {
                
                return Double(preferences.primarySeekLengthConstant)
                
            } else if let trackDuration = playingTrack?.duration {
                
                // Percentage of track duration
                let percentage = Double(preferences.primarySeekLengthPercentage)
                return trackDuration * percentage / 100.0
            }
            
        } else {
            
            // Continuous seeking
            return preferences.seekLength_continuous
        }
        
        // Default value
        return 5
    }
    
    /*
        Computes the seek length (i.e. interval/adjustment/delta) used as an increment/decrement when performing a "secondary" seek, i.e.
        the seeking that can only be performed through the application's menu (or associated keyboard shortcuts). There are no control buttons
        to directly perform secondary seeking.
    */
    private var secondarySeekLength: Double {
        
        if preferences.secondarySeekLengthOption == .constant {
            
            return Double(preferences.secondarySeekLengthConstant)
            
        } else if let trackDuration = playingTrack?.duration {
            
            // Percentage of track duration
            let percentage = Double(preferences.secondarySeekLengthPercentage)
            return trackDuration * percentage / 100.0
        }
        
        // Default value
        return 30
    }
    
    func seekToPercentage(_ percentage: Double) {
        
        if let track = playingTrack {
            forceSeek(percentage * track.duration / 100)
        }
    }
    
    func seekToTime(_ seconds: Double) {
        forceSeek(seconds)
    }
    
    // A forced seek can seek outside the bounds of a segment loop (if one is defined).
    // It occurs, for instance, when clicking on the seek bar, or using the "Jump to time" function.
    private func forceSeek(_ seekPosn: Double) {
        
        if state.isPlayingOrPaused, let track = playingTrack {
            
            let seekResult = player.forceSeekToTime(track, seekPosn)
            
            if seekResult.trackPlaybackCompleted {
                trackPlaybackCompleted()
                
            } else if seekResult.loopRemoved {
                SyncMessenger.publishNotification(PlaybackLoopChangedNotification.instance)
            }
        }
    }
    
    // MARK: Variables that indicate the current player state
    
    var state: PlaybackState {
        return player.state
    }
    
    var seekPosition: (timeElapsed: Double, percentageElapsed: Double, trackDuration: Double) {
        
        if let track = playingTrack {
            
            let elapsedTime: Double = player.seekPosition
            let duration: Double = track.duration
            
            return (elapsedTime, elapsedTime * 100 / duration, duration)
        }
        
        return (0, 0, 0)
    }
    
    var currentTrack: Track? {
        return sequencer.currentTrack
    }
    
    var playingTrack: Track? {
        return state.isPlayingOrPaused ? sequencer.currentTrack : nil
    }
    
    var waitingTrack: Track? {
        return state == .waiting ? sequencer.currentTrack : nil
    }
    
    var transcodingTrack: Track? {
        return state == .transcoding ? sequencer.currentTrack : nil
    }
    
    var playingTrackStartTime: TimeInterval? {
        return player.playingTrackStartTime
    }
    
    var playbackLoop: PlaybackLoop? {
        return player.playbackLoop
    }
    
    private func savePlaybackProfile() {
        
        if let track = playingTrack {
            profiles.add(track, PlaybackProfile(track, seekPosition.timeElapsed))
        }
    }
    
    // Saves playback settings for the current track if required by the preferences and existing profiles.
    private func savePlaybackProfileIfNeeded(_ track: Track, _ position: Double? = nil) {
        
        // Save playback settings if the option either requires saving settings for all tracks, or if
        // the option has been set for this particular playing track.
        if preferences.rememberLastPosition,
            preferences.rememberLastPositionOption == .allTracks || profiles.hasFor(track) {
            
            // Remember the current playback settings the next time this track plays.
            // Update the profile with the latest settings for this track.
            
            // If a specific position has been specified, use it. Otherwise, use the current seek position.
            // NOTE - If the seek position has reached the end of the track, the profile position will be reset to 0.
            let lastPosition = position ?? (seekPosition.timeElapsed >= track.duration ? 0 : seekPosition.timeElapsed)
            profiles.add(track, PlaybackProfile(track, lastPosition))
        }
    }
    
    private func deletePlaybackProfile() {
        
        if let track = playingTrack {
            profiles.remove(track)
        }
    }
    
    // This function is invoked when the user attempts to exit the app. It checks if there
    // is a track playing and if playback settings for the track need to be remembered.
    private func onExit() -> AppExitResponse {
        
        if let track = playingTrack {
            savePlaybackProfileIfNeeded(track)
        }
        
        // Proceed with exit
        return AppExitResponse.okToExit
    }
    
    // MARK: Message handling
    
    func consumeAsyncMessage(_ message: AsyncMessage) {
        
        if let completionMsg = message as? PlaybackCompletedAsyncMessage {
            
            trackPlaybackCompleted(completionMsg.session)
            return
        }
    }
    
    func consumeMessage(_ message: ActionMessage) {
        
        switch message.actionType {
            
        case .savePlaybackProfile:
            
            savePlaybackProfile()
            
        case .deletePlaybackProfile:
            
            deletePlaybackProfile()
            
        default: return
            
        }
    }
    
    func processRequest(_ request: RequestMessage) -> ResponseMessage {
        return request is AppExitRequest ? onExit() : EmptyResponse.instance
    }
    
    // ------------------- PlaylistChangeListenerProtocol methods ---------------------
    
    // TODO: Revisit all these functions
    
    func tracksAdded(_ addResults: [TrackAddResult]) {
        sequencer.tracksAdded(addResults)
    }
    
    func tracksReordered(_ moveResults: ItemMoveResults) {
        sequencer.tracksReordered(moveResults)
    }
    
    func playlistSorted(_ sortResults: SortResults) {
        sequencer.playlistSorted(sortResults)
    }
    
    func tracksRemoved(_ removeResults: TrackRemovalResults, _ playingTrackRemoved: Bool, _ removedPlayingTrack: Track?) {
    
        // Cannot continue playback if the playing track was removed from the playlist.
        playingTrackRemoved ? stop() : sequencer.tracksRemoved(removeResults, playingTrackRemoved, removedPlayingTrack)
    }
    
    // Stop playback when the playlist is cleared.
    func playlistCleared() {
        
        // Capture current track before the sequence is cleared
        let trackBeforeChange = currentTrack

        sequencer.playlistCleared()
        
        // Essentially stop()
        
        let stateBeforeChange = state
        
        if stateBeforeChange != .noTrack {
            
            let seekPositionBeforeChange = seekPosition.timeElapsed
            let requestContext = PlaybackRequestContext(stateBeforeChange, trackBeforeChange, seekPositionBeforeChange, nil, PlaybackParams.defaultParams())
            stopPlaybackChain.execute(requestContext)
        }
    }
}
