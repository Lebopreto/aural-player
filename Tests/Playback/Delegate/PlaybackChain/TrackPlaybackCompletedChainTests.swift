import XCTest

class TrackPlaybackCompletedChainTests: AuralTestCase, MessageSubscriber, AsyncMessageSubscriber {
    
    var startPlaybackChain: TestableStartPlaybackChain!
    var stopPlaybackChain: TestableStopPlaybackChain!
    
    var chain: TrackPlaybackCompletedChain!
    
    var player: TestablePlayer!
    var mockPlayerGraph: MockPlayerGraph!
    var mockScheduler: MockScheduler!
    var mockPlayerNode: MockPlayerNode!
    
    var playlist: TestablePlaylist!
    
    var sequencer: MockSequencer!
    var transcoder: MockTranscoder!
    var preferences: PlaybackPreferences!
    var profiles: PlaybackProfiles!
    
    var preTrackChangeMsgCount: Int = 0
    var preTrackChangeMsg_currentTrack: Track?
    var preTrackChangeMsg_currentState: PlaybackState?
    var preTrackChangeMsg_newTrack: Track?
    
    var trackTransitionMsgCount: Int = 0
    var trackTransitionMsg_currentTrack: Track?
    var trackTransitionMsg_currentState: PlaybackState?
    var trackTransitionMsg_newTrack: Track?
    
    var gapStartedMsgCount: Int = 0
    var gapStartedMsg_oldTrack: Track?
    var gapStartedMsg_newTrack: Track?
    var gapStartedMsg_endTime: Date?
    
    var trackNotPlayedMsgCount: Int = 0
    var trackNotPlayedMsg_oldTrack: Track?
    var trackNotPlayedMsg_error: InvalidTrackError?

    override func setUp() {
        
        mockPlayerGraph = MockPlayerGraph()
        mockPlayerNode = (mockPlayerGraph.playerNode as! MockPlayerNode)
        mockScheduler = MockScheduler(mockPlayerNode)
        
        player = TestablePlayer(mockPlayerGraph, mockScheduler)
        sequencer = MockSequencer()
        transcoder = MockTranscoder()
        
        preferences = PlaybackPreferences([:])
        profiles = PlaybackProfiles()
        
        let flatPlaylist = FlatPlaylist()
        let artistsPlaylist = GroupingPlaylist(.artists, .artist)
        let albumsPlaylist = GroupingPlaylist(.albums, .album)
        let genresPlaylist = GroupingPlaylist(.genres, .genre)
        
        playlist = TestablePlaylist(flatPlaylist, [artistsPlaylist, albumsPlaylist, genresPlaylist])
        
        startPlaybackChain = TestableStartPlaybackChain(player, sequencer, playlist, transcoder, profiles, preferences)
        stopPlaybackChain = TestableStopPlaybackChain(player, sequencer, transcoder, profiles, preferences)
        
        chain = TrackPlaybackCompletedChain(startPlaybackChain, stopPlaybackChain, sequencer, playlist, preferences)
        
        SyncMessenger.subscribe(messageTypes: [.preTrackChangeNotification], subscriber: self)
        AsyncMessenger.subscribe([.trackTransition, .trackNotPlayed], subscriber: self, dispatchQueue: DispatchQueue.global(qos: .userInteractive))
    }
    
    override func tearDown() {
        
        SyncMessenger.unsubscribe(messageTypes: [.preTrackChangeNotification], subscriber: self)
        AsyncMessenger.unsubscribe([.trackTransition, .trackNotPlayed], subscriber: self)
        
        AsyncMessenger.unsubscribe([.transcodingFinished], subscriber: startPlaybackChain)
    }
    
    func consumeNotification(_ notification: NotificationMessage) {
        
        if let msg = notification as? PreTrackChangeNotification {
            
            preTrackChangeMsgCount.increment()
            
            preTrackChangeMsg_currentTrack = msg.oldTrack
            preTrackChangeMsg_currentState = msg.oldState
            preTrackChangeMsg_newTrack = msg.newTrack
            
            return
        }
    }
    
    func consumeAsyncMessage(_ message: AsyncMessage) {
        
        if let trackTransitionMsg = message as? TrackTransitionAsyncMessage {
            
            if trackTransitionMsg.gapStarted {
                
                gapStartedMsgCount.increment()
                
                gapStartedMsg_oldTrack = trackTransitionMsg.beginTrack
                gapStartedMsg_endTime = trackTransitionMsg.gapEndTime
                gapStartedMsg_newTrack = trackTransitionMsg.endTrack
                
            } else if trackTransitionMsg.playbackStarted || trackTransitionMsg.playbackEnded {
            
                trackTransitionMsgCount.increment()
                
                trackTransitionMsg_currentTrack = trackTransitionMsg.beginTrack
                trackTransitionMsg_currentState = trackTransitionMsg.beginState
                trackTransitionMsg_newTrack = trackTransitionMsg.endTrack
            }
            
            return
            
        } else if let trackNotPlayedMsg = message as? TrackNotPlayedAsyncMessage {
            
            trackNotPlayedMsgCount.increment()
            trackNotPlayedMsg_oldTrack = trackNotPlayedMsg.oldTrack
            trackNotPlayedMsg_error = trackNotPlayedMsg.error
            
            return
        }
    }
    
    func testTrackPlaybackCompleted_noSubsequentTrack() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        sequencer.subsequentTrack = nil
        
        let oldProfile = PlaybackProfile(completedTrack, 125.324235346746)
        profiles.add(completedTrack, oldProfile)
        XCTAssertNotNil(profiles.get(completedTrack))
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        preferences.rememberLastPosition = true
        preferences.rememberLastPositionOption = .individualTracks
        
        chain.execute(context)
        
        // Ensure profile was reset to 0
        let newProfile = profiles.get(completedTrack)!
        XCTAssertEqual(newProfile.lastPosition, 0)
        
        assertTrackChange(completedTrack, .playing, nil)
    }
    
    func testTrackPlaybackCompleted_noSubsequentTrack_gapAfterCompletedTrack_noDelay() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        sequencer.subsequentTrack = nil
        
        playlist.setGapsForTrack(completedTrack, nil, PlaybackGap(3, .afterTrack))
        XCTAssertNotNil(playlist.getGapAfterTrack(completedTrack))
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertNil(context.requestedTrack)
        
        // No delay (because there is no subsequent track)
        XCTAssertNil(context.delay)
        
        assertTrackChange(completedTrack, .playing, nil)
    }
    
    func testTrackPlaybackCompleted_noSubsequentTrack_gapBetweenTracks_noDelay() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        sequencer.subsequentTrack = nil
        
        preferences.gapBetweenTracks = true
        preferences.gapBetweenTracksDuration = 3
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertNil(context.requestedTrack)
        
        // No delay (because there is no subsequent track)
        XCTAssertNil(context.delay)
        
        assertTrackChange(completedTrack, .playing, nil)
    }
    
    func testTrackPlaybackCompleted_subsequentTrackInvalid() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", 420, isValid: false)
        sequencer.subsequentTrack = subsequentTrack
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        assertTrackNotPlayed(completedTrack, subsequentTrack)
    }
    
    func testTrackPlaybackCompleted_hasSubsequentTrack() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", 420)
        sequencer.subsequentTrack = subsequentTrack
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        assertTrackChange(completedTrack, .playing, subsequentTrack)
    }
    
    func testTrackPlaybackCompleted_hasSubsequentTrack_completedTrackHasPlaybackProfile_resetTo0() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", 420)
        sequencer.subsequentTrack = subsequentTrack
        
        let oldProfile = PlaybackProfile(completedTrack, 125.324235346746)
        profiles.add(completedTrack, oldProfile)
        XCTAssertNotNil(profiles.get(completedTrack))
        
        preferences.rememberLastPosition = true
        preferences.rememberLastPositionOption = .individualTracks
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        // Ensure profile was reset to 0
        let newProfile = profiles.get(completedTrack)!
        XCTAssertEqual(newProfile.lastPosition, 0)
        
        assertTrackChange(completedTrack, .playing, subsequentTrack)
    }
    
    func testTrackPlaybackCompleted_gapAfterCompletedTrack_hasSubsequentTrack() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", 420)
        sequencer.subsequentTrack = subsequentTrack
        
        playlist.setGapsForTrack(completedTrack, nil, PlaybackGap(3, .afterTrack))
        XCTAssertNotNil(playlist.getGapAfterTrack(completedTrack))
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        XCTAssertEqual(context.delay!, playlist.getGapAfterTrack(completedTrack)!.duration)
        
        assertGapStarted(completedTrack, subsequentTrack)
        
        justWait(context.delay!)
        assertTrackChange(subsequentTrack, .waiting, subsequentTrack)
    }
    
    func testTrackPlaybackCompleted_gapAfterCompletedTrack_invalidSubsequentTrack() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", 420, isValid: false)
        sequencer.subsequentTrack = subsequentTrack
        
        playlist.setGapsForTrack(completedTrack, nil, PlaybackGap(3, .afterTrack))
        XCTAssertNotNil(playlist.getGapAfterTrack(completedTrack))
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        XCTAssertEqual(context.delay!, playlist.getGapAfterTrack(completedTrack)!.duration)
        
        assertGapNotStarted()
        assertTrackNotPlayed(completedTrack, subsequentTrack)
    }
    
    func testTrackPlaybackCompleted_gapBetweenTracks_hasSubsequentTrack() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", 420)
        sequencer.subsequentTrack = subsequentTrack
        
        preferences.gapBetweenTracks = true
        preferences.gapBetweenTracksDuration = 3
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        XCTAssertEqual(context.delay!, Double(preferences.gapBetweenTracksDuration))
        
        assertGapStarted(completedTrack, subsequentTrack)
        
        justWait(context.delay!)
        assertTrackChange(subsequentTrack, .waiting, subsequentTrack)
    }
    
    func testTrackPlaybackCompleted_subsequentTrackNeedsTranscoding() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", "ogg", 420)
        sequencer.subsequentTrack = subsequentTrack
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        XCTAssertFalse(subsequentTrack.lazyLoadingInfo.preparedForPlayback)
        XCTAssertTrue(subsequentTrack.lazyLoadingInfo.needsTranscoding)
        XCTAssertFalse(subsequentTrack.lazyLoadingInfo.preparationFailed)
        
        XCTAssertEqual(transcoder.transcodeImmediatelyCallCount, 1)
        XCTAssertEqual(transcoder.transcodeImmediately_track, subsequentTrack)
        
        XCTAssertEqual(player.state, .transcoding)
        
        // Simulate transcoding finished
        subsequentTrack.prepareWithAudioFile(URL(fileURLWithPath: "/Dummy/AudioFile.m4a"))
        AsyncMessenger.publishMessage(TranscodingFinishedAsyncMessage(subsequentTrack, true))
        justWait(0.5)
        
        assertTrackChange(subsequentTrack, .transcoding, subsequentTrack)
    }
    
    func testTrackPlaybackCompleted_subsequentTrackNeedsTranscoding_transcodingFailed() {
        
        let completedTrack = createTrack("Hydropoetry Cathedra", 597)
        let subsequentTrack = createTrack("Silene", "ogg", 420)
        sequencer.subsequentTrack = subsequentTrack
        
        let context = PlaybackRequestContext(.playing, completedTrack, completedTrack.duration, nil, PlaybackParams.defaultParams())
        
        chain.execute(context)
        
        XCTAssertEqual(context.requestedTrack!, subsequentTrack)
        
        XCTAssertFalse(subsequentTrack.lazyLoadingInfo.preparedForPlayback)
        XCTAssertTrue(subsequentTrack.lazyLoadingInfo.needsTranscoding)
        XCTAssertFalse(subsequentTrack.lazyLoadingInfo.preparationFailed)
        
        XCTAssertEqual(transcoder.transcodeImmediatelyCallCount, 1)
        XCTAssertEqual(transcoder.transcodeImmediately_track, subsequentTrack)
        
        XCTAssertEqual(player.state, .transcoding)
        
        // Simulate transcoding failed
        subsequentTrack.lazyLoadingInfo.preparationFailed(NoAudioTracksError(subsequentTrack))
        AsyncMessenger.publishMessage(TranscodingFinishedAsyncMessage(subsequentTrack, false))
        justWait(0.5)
        
        assertTrackNotPlayed(subsequentTrack, subsequentTrack)
    }
    
    private func assertTrackNotPlayed(_ oldTrack: Track, _ newTrack: Track) {

        XCTAssertEqual(player.state, .noTrack)
        XCTAssertEqual(preTrackChangeMsgCount, 0)
        
        executeAfter(0.5) {
            
            XCTAssertEqual(self.trackTransitionMsgCount, 0)
            
            XCTAssertEqual(self.trackNotPlayedMsgCount, 1)
            XCTAssertEqual(self.trackNotPlayedMsg_oldTrack, oldTrack)
            XCTAssertEqual(self.trackNotPlayedMsg_error!.track, newTrack)
        }
    }
    
    private func assertTrackChange(_ currentTrack: Track?, _ currentState: PlaybackState, _ newTrack: Track?) {
        
        let trackChanged = currentTrack != newTrack
        
        XCTAssertEqual(preTrackChangeMsgCount, trackChanged ? 1 : 0)
        
        if trackChanged {
            
            XCTAssertEqual(preTrackChangeMsg_currentTrack, currentTrack)
            XCTAssertEqual(preTrackChangeMsg_currentState, currentState)
            XCTAssertEqual(preTrackChangeMsg_newTrack, newTrack)
        }
        
        XCTAssertEqual(player.state, newTrack == nil ? .noTrack : .playing)
        
        XCTAssertEqual(startPlaybackChain.executionCount, newTrack == nil ? 0 : 1)
        XCTAssertEqual(stopPlaybackChain.executionCount, newTrack == nil ? 1 : 0)
        
        executeAfter(0.5) {
        
            XCTAssertEqual(self.trackTransitionMsgCount, 1)
            XCTAssertEqual(self.trackTransitionMsg_currentTrack, currentTrack)
            XCTAssertEqual(self.trackTransitionMsg_currentState, currentState)
            XCTAssertEqual(self.trackTransitionMsg_newTrack, newTrack)
        }
    }
    
    private func assertGapStarted(_ oldTrack: Track?, _ newTrack: Track) {
        
        XCTAssertEqual(player.state, PlaybackState.waiting)
        
        executeAfter(0.5) {
            
            XCTAssertEqual(self.gapStartedMsgCount, 1)
            XCTAssertEqual(self.gapStartedMsg_oldTrack, oldTrack)
            XCTAssertEqual(self.gapStartedMsg_newTrack!, newTrack)
            XCTAssertEqual(self.gapStartedMsg_endTime!.compare(Date()), ComparisonResult.orderedDescending)
        }
    }
    
    private func assertGapNotStarted() {
        
        executeAfter(0.5) {
            XCTAssertEqual(self.gapStartedMsgCount, 0)
        }
    }
}
