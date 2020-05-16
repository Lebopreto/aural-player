import Foundation

class PlaybackAction: PlaybackPreparationAction {
    
    private let player: PlayerProtocol
    
    var nextAction: PlaybackPreparationAction?
    
    init(_ player: PlayerProtocol) {
        self.player = player
    }
    
    func execute(_ context: PlaybackRequestContext) {
        
        guard let newTrack = context.requestedTrack else {return}
        
        let oldTrack = context.currentTrack
        let params = context.requestParams
        
        SyncMessenger.publishNotification(PreTrackChangeNotification(oldTrack, context.currentState, newTrack))
        
        player.play(newTrack.track, params.startPosition ?? 0, params.endPosition)
        
        AsyncMessenger.publishMessage(TrackChangedAsyncMessage(oldTrack, context.currentState, newTrack))
        
        // Chain has completed execution, inform the request context.
        context.completed()
    }
}