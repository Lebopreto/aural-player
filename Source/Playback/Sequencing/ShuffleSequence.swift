/*
    Encapsulates a pre-computed shuffle sequence to be used to determine the order in which shuffled tracks will be played.
 */

import Foundation

class ShuffleSequence {
    
    // Array of sequence track indexes that constitute the shuffle sequence. This array must always be of the same size as the parent playback sequence
    private(set) var sequence: [Int] = []
    
    var size: Int {
        return sequence.count
    }
    
    // The index, within this sequence, of the element representing the currently playing track index. i.e. this is NOT a track index ... it is an index of an index.
    private var curIndex: Int = -1
    
    // MARK: Sequence creation/mutation functions -------------------------------------------------------------------------
    
    // Recompute the sequence, with a given tracks count
    func resizeAndReshuffle(size: Int, startWith desiredStartValue: Int? = nil) {
        
        curIndex = desiredStartValue == nil ? -1 : 0
        
        if self.size != size {
            sequence = Array(0..<size)
        }
        
        // NOTE - If only one track in sequence, no need to do any adjustments.
        guard self.size > 1 else {return}
        
        sequence.shuffle()

        // Make sure that desiredStartValue is at index 0 in the new sequence.
        if let theStartValue = desiredStartValue, sequence.first != theStartValue, let indexOfStartValue = sequence.firstIndex(of: theStartValue) {
            sequence.swapAt(0, indexOfStartValue)
        }
    }
    
    // Called when the sequence ends.
    func reShuffle(dontStartWith value: Int) {
        
        curIndex = -1
        
        // NOTE - If only one track in sequence, no need to do any adjustments.
        guard size > 1 else {return}
        
        sequence.shuffle()
        
        // Ensure that the first element of the new sequence is different from
        // the last element of the previous sequence, so that no track is played twice in a row.
        if sequence.first == value {
            sequence.swapAt(0, size - 1)
        }
    }
    
    // Clear the sequence
    func clear() {
        
        sequence.removeAll()
        curIndex = -1
    }
    
    // MARK: Sequence iteration functions and properties -----------------------------------------------------------------
    
    // Retreat the cursor by one index and retrieve the element at the new index, if available
    func previous() -> Int? {
        return hasPrevious ? sequence[curIndex.decrementAndGet()] : nil
    }
    
    // Advance the cursor by one index and retrieve the element at the new index, if available
    func next(repeatMode: RepeatMode) -> Int? {
        
        if repeatMode == .all, hasEnded {
            reShuffle(dontStartWith: sequence[curIndex])
        }
        
        return hasNext ? sequence[curIndex.incrementAndGet()] : nil
    }
    
    // Retrieve the previous element, if available, without retreating the cursor. This is useful when trying to predict the previous track in the sequence (to perform some sort of preparation) without actually playing it.
    func peekPrevious() -> Int? {
        return hasPrevious ? sequence[curIndex - 1] : nil
    }
    
    // Retrieve the next element, if available, without advancing the cursor. This is useful when trying to predict the next track in the sequence (to perform some sort of preparation) without actually playing it.
    func peekNext() -> Int? {
        return hasNext ? sequence[curIndex + 1] : nil
    }
    
    // Checks if it is possible to advance the cursor
    var hasNext: Bool {
        return size > 0 && curIndex < size - 1
    }
    
    // Checks if it is possible to retreat the cursor
    var hasPrevious: Bool {
        return curIndex > 0
    }
    
    // Checks if all elements have been visited, i.e. the end of the sequence has been reached
    var hasEnded: Bool {
        return curIndex == size - 1
    }
}
