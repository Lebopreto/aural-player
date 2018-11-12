import Cocoa

class FilterPresetsEditorViewController: FXPresetsEditorGenericViewController {
    
    @IBOutlet weak var filterView: FilterView!
    private var bandsDataSource: PresetFilterBandsDataSource = PresetFilterBandsDataSource()
    
    override var nibName: String? {return "FilterPresetsEditor"}
    
    var filterUnit: FilterUnitDelegate {return graph.filterUnit}
    
    override func awakeFromNib() {
        
        super.awakeFromNib()
        
        unitType = .filter
        fxUnit = filterUnit
        presetsWrapper = PresetsWrapper<FilterPreset, FilterPresets>(filterUnit.presets)
    }
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        let bandsDataFunction = {() -> [FilterBand] in return self.getFilterChartBands()}
        filterView.initialize({() -> EffectsUnitState in return .active}, bandsDataFunction, bandsDataSource, false)
    }
    
    override func renderPreview(_ presetName: String) {
        
        let preset = filterUnit.presets.presetByName(presetName)!
        bandsDataSource.preset = preset
        filterView.refresh()
    }
    
    private func getFilterChartBands() -> [FilterBand] {
        
        let selection = getSelectedPresetNames()
        if !selection.isEmpty {
            return filterUnit.presets.presetByName(selection[0])!.bands
        }
        
        return []
    }
}

class PresetFilterBandsDataSource: FilterBandsDataSource {
    
    var preset: FilterPreset?
    
    func countFilterBands() -> Int {
        return preset?.bands.count ?? 0
    }
    
    func getFilterBand(_ index: Int) -> FilterBand {
        return preset!.bands[index]
    }
}
