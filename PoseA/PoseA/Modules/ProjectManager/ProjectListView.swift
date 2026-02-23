//
//  ProjectListView.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/23.
//

// ProjectListView.swift
import SwiftUI

struct ProjectListView: View {
    @Binding var isPresented: Bool
    let onLoad: (GymProject, [Int: [KeypointData]]?) -> Void
    
    @State private var projectManager = ProjectManager.shared
    @State private var projectToDelete: GymProject?
    
    var body: some View {
        NavigationView {
            Group {
                if projectManager.savedProjects.isEmpty {
                    ContentUnavailableView("No Projects",
                                           systemImage: "folder",
                                           description: Text("Save a project first to see it here."))
                } else {
                    List {
                        ForEach(projectManager.savedProjects) { project in
                            ProjectRowView(project: project)
                                .contentShape(Rectangle())
                                .onTapGesture { loadProject(project) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        projectToDelete = project
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .confirmationDialog("Delete Project?",
                                isPresented: Binding(get: { projectToDelete != nil },
                                                     set: { if !$0 { projectToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let p = projectToDelete {
                        projectManager.deleteProject(id: p.id)
                    }
                }
            }
        }
    }
    
    private func loadProject(_ project: GymProject) {
        let keypoints = ProjectManager.shared.loadKeypointsForProject(id: project.id)
        onLoad(project, keypoints)
        isPresented = false
    }
}
struct ProjectRowView: View {
    let project: GymProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(project.actionType.displayName, systemImage: project.actionType.preset.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(project.recordedDate, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(project.projectName).font(.headline)
            
            // Athlete info line
            if !project.athlete.name.isEmpty {
                HStack(spacing: 8) {
                    Text(project.athlete.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let age = project.athlete.age {
                        Text("· \(age) yrs").font(.caption).foregroundColor(.secondary)
                    }
                    if let h = project.athlete.heightCm {
                        Text("· \(String(format: "%.0f", h)) cm").font(.caption).foregroundColor(.secondary)
                    }
                    if let w = project.athlete.weightKg {
                        Text("· \(String(format: "%.1f", w)) kg").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            
            HStack(spacing: 8) {
                Badge(text: project.isAnalysisAvailable ? "Analyzed" : "No Analysis",
                      color: project.isAnalysisAvailable ? .green : .orange)
                Badge(text: project.calibrationData?.isCalibrated == true ? "Calibrated" : "Uncalibrated",
                      color: project.calibrationData?.isCalibrated == true ? .blue : .gray)
            }
            
            Text("Modified \(project.lastModifiedDate, style: .relative) ago")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
