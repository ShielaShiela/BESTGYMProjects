//
//  SaveProjectView.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/23.
//

// SaveProjectSheet.swift
import SwiftUI
struct SaveProjectSheet: View {
    @Binding var isPresented: Bool
    let appState: MainAppState
    let mediaManager: MediaManagerVM
    let calibrationModel: CalibrationModel
    let onSave: (GymProject) -> Void
    
    @State private var project: GymProject
    @State private var isSaving = false
    @State private var saveError: String?
    
    // For the action type picker
    @State private var selectedPreset: ActionTypePreset = .giantSwing
    @State private var customActionName: String = ""
    @FocusState private var customFieldFocused: Bool
    
    // Unit toggle (cosmetic only — always store metric internally)
    @State private var useImperial: Bool = false
    
    // Temp strings for optional numeric fields
    @State private var ageText: String = ""
    @State private var heightText: String = ""
    @State private var weightText: String = ""
    
    init(isPresented: Binding<Bool>,
         appState: MainAppState,
         mediaManager: MediaManagerVM,
         calibrationModel: CalibrationModel,
         existingProject: GymProject? = nil,
         onSave: @escaping (GymProject) -> Void) {
        self._isPresented = isPresented
        self.appState = appState
        self.mediaManager = mediaManager
        self.calibrationModel = calibrationModel
        self.onSave = onSave
        
        let proj = existingProject ?? GymProject(
            projectName: appState.sourceFileName.isEmpty ? "New Project" : appState.sourceFileName,
            athlete: AthleteProfile(),
            actionType: .giantSwing,
            recordedDate: Date(),
            sourceFileName: appState.sourceFileName
        )
        self._project = State(wrappedValue: proj)
        
        // Pre-fill text fields from existing
        self._selectedPreset = State(wrappedValue: proj.actionType.preset)
        self._customActionName = State(wrappedValue: proj.actionType.customName)
        self._ageText = State(wrappedValue: proj.athlete.age.map { String($0) } ?? "")
        self._heightText = State(wrappedValue: proj.athlete.heightCm.map { String(format: "%.1f", $0) } ?? "")
        self._weightText = State(wrappedValue: proj.athlete.weightKg.map { String(format: "%.1f", $0) } ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                
                // MARK: Project Info
                Section("Project Info") {
                    TextField("Project Name", text: $project.projectName)
                    DatePicker("Date Recorded",
                               selection: $project.recordedDate,
                               displayedComponents: .date)
                }
                
                // MARK: Action Type
                Section {
                    Picker("Skill / Action", selection: $selectedPreset) {
                        ForEach(ActionTypePreset.allCases, id: \.self) { preset in
                            Label(preset.rawValue, systemImage: preset.icon).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if selectedPreset == .custom {
                        HStack {
                            Image(systemName: "pencil")
                                .foregroundColor(.secondary)
                            TextField("e.g. Cassina, Deloche...", text: $customActionName)
                                .focused($customFieldFocused)
                                .onAppear { customFieldFocused = true }
                        }
                    } else {
                        // Show the selected skill label nicely
                        HStack {
                            Image(systemName: selectedPreset.icon)
                                .foregroundColor(.accentColor)
                            Text(selectedPreset.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Skill / Action Type")
                } footer: {
                    Text("Choose a preset or enter a custom skill name.")
                        .font(.caption)
                }
                
                // MARK: Athlete Profile
                Section("Athlete") {
                    TextField("Athlete Name", text: $project.athlete.name)
                    
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("years", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    Toggle("Use Imperial (lb / ft)", isOn: $useImperial)
                        .tint(.accentColor)
                    
                    HStack {
                        Text(useImperial ? "Height" : "Height")
                        Spacer()
                        TextField(useImperial ? "ft  e.g. 5.9" : "cm  e.g. 170", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(useImperial ? "ft" : "cm")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField(useImperial ? "lb" : "kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(useImperial ? "lb" : "kg")
                            .foregroundColor(.secondary)
                    }
                    
                    

                }
                
                // MARK: Notes
                Section("Notes") {
                    TextEditor(text: $project.notes)
                        .frame(minHeight: 70)
                }
                
                // MARK: Status Summary
                Section("Data Status") {
                    LabeledContent("Source File", value: project.sourceFileName.isEmpty ? "None" : project.sourceFileName)
                    LabeledContent("Keypoints",   value: mediaManager.isKeypointAvailable ? "✅ Available" : "❌ Not loaded")
                    LabeledContent("Calibration", value: calibrationModel.isCalibrated ? "✅ Calibrated" : "⚠️ Not calibrated")
                    LabeledContent("Analysis",    value: appState.isAnalysisAvailable ? "✅ Done" : "⚠️ Not run")
                }
                
                if let error = saveError {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
                if appState.sourceURL != nil {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.secondary)
                            Text("Media copy: \(estimatedSize)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                
            }
            .navigationTitle("Save Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { performSave() }
                        .disabled(isSaving || project.projectName.isEmpty || !isCustomActionValid)
                        .overlay {
                            if isSaving { ProgressView().scaleEffect(0.7) }
                        }
                }
            }
        }
    }
    
    // Custom name must not be blank if .custom is selected
    private var isCustomActionValid: Bool {
        selectedPreset != .custom || !customActionName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var estimatedSize: String {
        ProjectManager.shared.estimatedSourceSize(sourceURL: appState.sourceURL)
    }

    private func performSave() {
        isSaving = true
        saveError = nil
        
        // Build action type
        project.actionType = selectedPreset == .custom
        ? .custom(customActionName.trimmingCharacters(in: .whitespaces))
        : .preset(selectedPreset)
        
        // Parse athlete fields — convert imperial to metric if needed
        project.athlete.age = Int(ageText)
        
        if let h = Double(heightText) {
            project.athlete.heightCm = useImperial ? h * 30.48 : h
        }
        if let w = Double(weightText) {
            project.athlete.weightKg = useImperial ? w * 0.453592 : w
        }
        
        // ✅ Capture calibration using actual CalibrationModel properties
        project.calibrationData = SavedCalibration(
            isCalibrated:   calibrationModel.isCalibrated,
            barTopPoint:    calibrationModel.barTopPoint.map    { CGPointCodable($0) },
            barBottomPoint: calibrationModel.barBottomPoint.map { CGPointCodable($0) },
            realBarHeightCm: calibrationModel.realBarHeightCm
        )
        project.isAnalysisAvailable = appState.isAnalysisAvailable
        
        let keypointsData = mediaManager.fileLoaderViewModel.isKeyLoaded
        ? mediaManager.fileLoaderViewModel.keypointsByFrame
        : nil
        
        
        ProjectManager.shared.saveProject(
            &project,
            keypointsData: mediaManager.fileLoaderViewModel.keypointsByFrame,
            sourceURL: appState.sourceURL        // ← ADD THIS
        ) { result in
            switch result {
            case .success:
                onSave(project)
                isPresented = false
            case .failure(let error):
                print("Save failed: \(error.localizedDescription)")            }
        }
    }
}
