/*
    View controller that handles the assembly of the player view tree from its multiple pieces, and switches between high-level views depending on current player state (i.e. playing / transcoding / stopped, etc).
 
    The player view tree consists of:
        
        - Playing track info (track info, art, etc)
            - Default view
            - Expanded Art view
 
        - Waiting track info (when a track is waiting to play after a delay)
 
        - Transcoder info (when a track is being transcoded)
 
        - Player controls (play/seek, next/previous track, repeat/shuffle, volume/balance)
 
        - Functions toolbar (detailed track info / favorite / bookmark, etc)
 */
import Cocoa

class PlayerViewController: NSViewController, MessageSubscriber, AsyncMessageSubscriber {
    
    private var playingTrackView: PlayingTrackView = ViewFactory.playingTrackView as! PlayingTrackView
    private var waitingTrackView: NSView = ViewFactory.waitingTrackView
    private var transcodingTrackView: NSView = ViewFactory.transcodingTrackView
    
    // Delegate that conveys all seek and playback info requests to the player
    private let player: PlaybackInfoDelegateProtocol = ObjectGraph.playbackInfoDelegate
    
    override var nibName: String? {return "Player"}
    
    override func viewDidLoad() {
        
        [playingTrackView, waitingTrackView, transcodingTrackView].forEach({
            
            self.view.addSubview($0)
            $0.setFrameOrigin(NSPoint.zero)
        })
        
        initSubscriptions()
        switchView()
    }
    
    private func initSubscriptions() {
        
        AsyncMessenger.subscribe([.trackTransition], subscriber: self, dispatchQueue: DispatchQueue.main)
    }
    
    // Depending on current player state, switch to one of the 3 views.
    private func switchView() {
        
        switch player.state {

        case .noTrack, .playing, .paused:
            
            NSView.hideViews(waitingTrackView, transcodingTrackView)
            playingTrackView.showView()

        case .waiting:
            
            playingTrackView.hideView()
            transcodingTrackView.hide()
            
            waitingTrackView.show()

        case .transcoding:
            
            playingTrackView.hideView()
            waitingTrackView.hide()
            
            transcodingTrackView.show()
        }
    }
    
    // MARK: Message handling
    
    func consumeAsyncMessage(_ message: AsyncMessage) {
        
        if let trackTransitionMsg = message as? TrackTransitionAsyncMessage {
            
            SyncMessenger.publishNotification(TrackTransitionNotification(trackTransitionMsg.beginTrack, trackTransitionMsg.beginState, trackTransitionMsg.endTrack, trackTransitionMsg.endState, trackTransitionMsg.gapEndTime))
            
            switchView()
            return
        }
    }
}
