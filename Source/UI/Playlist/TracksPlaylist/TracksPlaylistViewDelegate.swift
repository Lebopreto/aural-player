import Cocoa

/*
    Delegate for the NSTableView that displays the "Tracks" (flat) playlist view.
 */
class TracksPlaylistViewDelegate: NSObject, NSTableViewDelegate {
    
    // TODO: Reduce code duplication in the cell creation and constraint code
    
    @IBOutlet weak var playlistView: NSTableView!
    
    // Delegate that relays accessor operations to the playlist
    private let playlist: PlaylistAccessorDelegateProtocol = ObjectGraph.playlistAccessorDelegate
    
    // Used to determine the currently playing track
    private let playbackInfo: PlaybackInfoDelegateProtocol = ObjectGraph.playbackInfoDelegate
    
    private var cachedGapImage: NSImage!
    
    override func awakeFromNib() {
        
        // Store the NSTableView in a variable for convenient subsequent access
        TableViewHolder.instance = playlistView
        cachedGapImage = Images.imgGap.applyingTint(Colors.Playlist.trackNameTextColor)
    }
    
    func changeGapIndicatorColor(_ color: NSColor) {
        cachedGapImage = Images.imgGap.applyingTint(Colors.Playlist.trackNameTextColor)
    }
    
    // Returns a view for a single row
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return FlatPlaylistRowView()
    }
    
    // Enables type selection, allowing the user to conveniently and efficiently find a playlist track by typing its display name, which results in the track, if found, being selected within the playlist
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        
        // Only the track name column is used for type selection
        let colID = tableColumn?.identifier.rawValue ?? ""
        if colID != UIConstants.playlistNameColumnID {
            return nil
        }
        
        return playlist.trackAtIndex(row)?.track.conciseDisplayName
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        
        if let track = playlist.trackAtIndex(row)?.track {
            
            let ga = playlist.getGapAfterTrack(track)
            let gb = playlist.getGapBeforeTrack(track)
            
            if ga != nil && gb != nil {
                return 61
            } else if ga != nil || gb != nil {
                return 43
            }
        }

        return 25
    }
    
    // Returns a view for a single column
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        if let track = playlist.trackAtIndex(row)?.track {
            
            let gapA = playlist.getGapAfterTrack(track)
            let gapB = playlist.getGapBeforeTrack(track)
            
            switch convertFromNSUserInterfaceItemIdentifier(tableColumn!.identifier) {
                
            case UIConstants.playlistIndexColumnID:
                
                let indexText: String = String(describing: row + 1)
                
                // TODO: switch is not required, just do an if-else-if
                switch playbackInfo.state {
                    
                    case .playing, .paused:
                        
                        if let playingTrack = self.playbackInfo.playingTrack,
                            let playingTrackIndex = self.playlist.indexOfTrack(playingTrack)?.index, playingTrackIndex == row {
                            
                            return createPlayingTrackImageCell(tableView, UIConstants.playlistIndexColumnID, indexText, gapB, gapA, row)
                        }
                    
                    case .transcoding:
                    
                        if let transcodingTrack = self.playbackInfo.transcodingTrack,
                            let transcodingTrackIndex = self.playlist.indexOfTrack(transcodingTrack)?.index, transcodingTrackIndex == row {
                            
                            return createTranscodingTrackImageCell(tableView, UIConstants.playlistIndexColumnID, indexText, gapB, gapA, row)
                        }
                    
                    case .waiting:
                        
                        if let waitingTrack = self.playbackInfo.waitingTrack,
                            let waitingTrackIndex = self.playlist.indexOfTrack(waitingTrack)?.index, waitingTrackIndex == row {
                            
                            return createWaitingImageCell(tableView, UIConstants.playlistIndexColumnID, indexText, gapB, gapA, row)
                        }
                    
                    case .noTrack:
                        
                        // Otherwise, create a text cell with the track index
                        return createIndexTextCell(tableView, UIConstants.playlistIndexColumnID, indexText, gapB, gapA, row)
                }
                
                return createIndexTextCell(tableView, UIConstants.playlistIndexColumnID, indexText, gapB, gapA, row)
                
            case UIConstants.playlistNameColumnID:
                
                return createTrackNameCell(tableView, UIConstants.playlistNameColumnID, track.conciseDisplayName, gapB, gapA, row)
                
            case UIConstants.playlistDurationColumnID:
                
                return createDurationCell(tableView, UIConstants.playlistDurationColumnID, ValueFormatter.formatSecondsToHMS(track.duration), gapB, gapA, row)
                
            default: return nil
                
            }
        }
        
        return nil
    }
    
    private func createIndexTextCell(_ tableView: NSTableView, _ id: String, _ text: String, _ gapBefore: PlaybackGap? = nil, _ gapAfter: PlaybackGap? = nil, _ row: Int) -> IndexCellView? {
     
        if let cell = tableView.makeView(withIdentifier: convertToNSUserInterfaceItemIdentifier(id), owner: nil) as? IndexCellView {
            
            cell.textField?.font = Fonts.Playlist.indexFont
            cell.textField?.stringValue = text
            cell.textField?.show()
            cell.textField?.backgroundColor = NSColor.yellow
            cell.imageView?.hide()
            cell.row = row
            
            let aOnly = gapAfter != nil && gapBefore == nil
            let bOnly = gapBefore != nil && gapAfter == nil
            
            if aOnly {
                
                cell.adjustIndexConstraints_afterGapOnly()
                
            } else if bOnly {
                
                cell.adjustIndexConstraints_beforeGapOnly()
                
            } else {
                
                cell.adjustIndexConstraints_centered()
            }
            
            return cell
        }
        
        return nil
    }
    
    private func createTrackNameCell(_ tableView: NSTableView, _ id: String, _ text: String, _ gapBefore: PlaybackGap? = nil, _ gapAfter: PlaybackGap? = nil, _ row: Int) -> TrackNameCellView? {
        
        if let cell = tableView.makeView(withIdentifier: convertToNSUserInterfaceItemIdentifier(id), owner: nil) as? TrackNameCellView {
            
            cell.textField?.font = Fonts.Playlist.trackNameFont
            
            cell.textField?.stringValue = text
            cell.textField?.show()
            cell.row = row
            
            let both = gapBefore != nil && gapAfter != nil
            let aOnly = gapAfter != nil && gapBefore == nil
            let bOnly = gapBefore != nil && gapAfter == nil
            
            if aOnly {
                
                cell.gapBeforeImg.hide()
                
                cell.gapAfterImg.image = cachedGapImage
                cell.gapAfterImg.show()
                
                cell.placeTextFieldOnTop()
                
            } else if bOnly {
                
                cell.gapBeforeImg.image = cachedGapImage
                cell.gapBeforeImg.show()
                
                cell.gapAfterImg.hide()
                
                cell.placeTextFieldBelowView(cell.gapBeforeImg)
                
            } else if both {
                
                cell.gapBeforeImg.image = cachedGapImage
                cell.gapBeforeImg.show()
                
                cell.gapAfterImg.image = cachedGapImage
                cell.gapAfterImg.show()
                
                cell.placeTextFieldBelowView(cell.gapBeforeImg)
                
            } else {
                
                // Neither
                cell.gapBeforeImg.hide()
                cell.gapAfterImg.hide()
                
                cell.placeTextFieldOnTop()
            }
            
            return cell
        }
        
        return nil
    }
    
    private func createDurationCell(_ tableView: NSTableView, _ id: String, _ text: String, _ gapBefore: PlaybackGap? = nil, _ gapAfter: PlaybackGap? = nil, _ row: Int) -> DurationCellView? {
        
        if let cell = tableView.makeView(withIdentifier: convertToNSUserInterfaceItemIdentifier(id), owner: nil) as? DurationCellView {
            
            cell.textField?.font = Fonts.Playlist.indexFont
            cell.textField?.stringValue = text
            cell.textField?.show()
            cell.row = row
            
            if cell.gapAfterTextField == nil {
                return cell
            }
            
            let both = gapBefore != nil && gapAfter != nil
            let aOnly = gapAfter != nil && gapBefore == nil
            let bOnly = gapBefore != nil && gapAfter == nil
            
            if aOnly {
                
                let gap = gapAfter!
                
                cell.gapBeforeTextField.hide()
                cell.gapAfterTextField.show()
                
                cell.gapAfterTextField.stringValue = ValueFormatter.formatSecondsToHMS(gap.duration)
                
                cell.placeTextFieldOnTop()
                
            } else if bOnly {
                
                let gap = gapBefore!
                
                cell.gapBeforeTextField.show()
                cell.gapAfterTextField.hide()
                
                cell.gapBeforeTextField.stringValue = ValueFormatter.formatSecondsToHMS(gap.duration)
                
                cell.placeTextFieldBelowView(cell.gapBeforeTextField)
                
            } else if both {
                
                let gapA = gapAfter!
                let gapB = gapBefore!
                
                cell.gapBeforeTextField.show()
                cell.gapAfterTextField.show()
                
                cell.gapBeforeTextField.stringValue = ValueFormatter.formatSecondsToHMS(gapB.duration)
                cell.gapAfterTextField.stringValue = ValueFormatter.formatSecondsToHMS(gapA.duration)
                
                cell.placeTextFieldBelowView(cell.gapBeforeTextField)
                
            } else {
                
                // Neither
                cell.gapBeforeTextField.hide()
                cell.gapAfterTextField.hide()
                
                cell.placeTextFieldOnTop()
            }
            
            return cell
        }
        
        return nil
    }
    
    // MARK: Constraints for Index cells
    
    // Creates a cell view containing the animation for the currently playing track
    private func createPlayingTrackImageCell(_ tableView: NSTableView, _ id: String, _ text: String, _ gapBefore: PlaybackGap? = nil, _ gapAfter: PlaybackGap? = nil, _ row: Int) -> IndexCellView? {
        
        return createIndexImageCell(tableView, id, text, gapBefore, gapAfter, row, Images.imgPlayingTrack.applyingTint(Colors.Playlist.playingTrackIconColor))
    }
    
    // Creates a cell view containing the animation for the currently playing track
    private func createTranscodingTrackImageCell(_ tableView: NSTableView, _ id: String, _ text: String, _ gapBefore: PlaybackGap? = nil, _ gapAfter: PlaybackGap? = nil, _ row: Int) -> IndexCellView? {
        
        return createIndexImageCell(tableView, id, text, gapBefore, gapAfter, row, Images.imgTranscodingTrack.applyingTint(Colors.Playlist.playingTrackIconColor))
    }
    
    // Creates a cell view containing the animation for the currently playing track
    private func createWaitingImageCell(_ tableView: NSTableView, _ id: String, _ text: String, _ gapBefore: PlaybackGap? = nil, _ gapAfter: PlaybackGap? = nil, _ row: Int) -> IndexCellView? {
        
        return createIndexImageCell(tableView, id, text, gapBefore, gapAfter, row, Images.imgWaitingTrack.applyingTint(Colors.Playlist.playingTrackIconColor))
    }
    
    private func createIndexImageCell(_ tableView: NSTableView, _ id: String, _ text: String, _ gapBefore: PlaybackGap? = nil, _ gapAfter: PlaybackGap? = nil, _ row: Int, _ image: NSImage) -> IndexCellView? {
        
        if let cell = tableView.makeView(withIdentifier: convertToNSUserInterfaceItemIdentifier(UIConstants.playlistIndexColumnID), owner: nil) as? IndexCellView {
            
            // Configure and show the image view
            let imgView = cell.imageView!
         
            imgView.image = image
            imgView.show()
            
            // Hide the text view
            cell.textField?.hide()
            
            cell.textField?.stringValue = text
            cell.row = row
            
            let aOnly = gapAfter != nil && gapBefore == nil
            let bOnly = gapBefore != nil && gapAfter == nil
            
            if aOnly {
                
                cell.adjustIndexConstraints_afterGapOnly()
                
            } else if bOnly {
                
                cell.adjustIndexConstraints_beforeGapOnly()
                
            } else {
                
                cell.adjustIndexConstraints_centered()
            }
            
            return cell
        }
        
        return nil
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSUserInterfaceItemIdentifier(_ input: NSUserInterfaceItemIdentifier) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToNSUserInterfaceItemIdentifier(_ input: String) -> NSUserInterfaceItemIdentifier {
	return NSUserInterfaceItemIdentifier(rawValue: input)
}
