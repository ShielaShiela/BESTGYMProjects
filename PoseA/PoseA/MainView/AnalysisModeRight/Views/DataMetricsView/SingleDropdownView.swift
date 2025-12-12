//
//  SingleDropdownView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/28/25.
//

import SwiftUI

struct SingleDropdownView: View {
    let options: [String]
    
    @Binding var selectedOption: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(selectedOption ?? "Select Joint")
                        .font(.caption)
                        .foregroundColor(selectedOption == nil ? .gray : .primary)
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
                                selectedOption = option
                                withAnimation {
                                    isExpanded = false
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
                                    if selectedOption == option {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(10)
                                .background(selectedOption == option ? Color.gray.opacity(0.2) : Color.white)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
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
