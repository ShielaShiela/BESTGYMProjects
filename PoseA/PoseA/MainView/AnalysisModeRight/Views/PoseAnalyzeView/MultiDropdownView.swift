//
//  MultiDropdownView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/13/25.
//

import SwiftUI

struct MultiDropdownView: View {
    let options: [String]
    
    @Binding var selectedOptions: Set<String>
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(selectedOptions.isEmpty ? "Select Joints" : selectedOptions.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(selectedOptions.isEmpty ? .gray : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(10)
                .frame(width: 150, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.6)))
            }

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(options.indices, id: \.self) { index in
                            let option = options[index]
                            Button {
                                if selectedOptions.contains(option) {
                                    selectedOptions.remove(option)
                                } else {
                                    selectedOptions.insert(option)
                                }
                            } label: {
                                HStack {
                                    Rectangle()
                                        .frame(width: 10, height: 10)
                                        .foregroundColor(jointColors[option])
                                    Text(option)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedOptions.contains(option) {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(10)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .background(Color.white)
                            
                            // Only show divider if not last item
                            if index < options.count - 1 {
                                Divider()
                                    .frame(width: 125)
                                    .padding(.leading)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
                .frame(width: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .background(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.6))
                    .background(Color.white))
            }
        }
    }
}
