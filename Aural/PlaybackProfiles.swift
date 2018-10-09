import Foundation

class PlaybackProfiles {
    
    // Track file -> Profile
    private static var map: [URL: PlaybackProfile] = [:]
    
    static func saveProfile(_ track: Track, _ lastPosition: Double) {
        map[track.file] = PlaybackProfile(file: track.file, lastPosition: lastPosition)
    }
    
    static func saveProfile(_ file: URL, _ lastPosition: Double) {
        map[file] = PlaybackProfile(file: file, lastPosition: lastPosition)
    }
    
    static func deleteProfile(_ track: Track) {
        map[track.file] = nil
    }
    
    static func profileForTrack(_ track: Track) -> PlaybackProfile? {
        return map[track.file]
    }
    
    static func removeAll() {
        map.removeAll()
    }
    
    static func getPersistentState() -> PlaybackProfilesState {

        let state = PlaybackProfilesState()
        state.profiles.append(contentsOf: map.values)

        return state
    }
}

struct PlaybackProfile {
    
    let file: URL
    
    // Last playback position
    let lastPosition: Double
    
    // TODO: Seek length ? Long for audiobooks, short for tracks
}