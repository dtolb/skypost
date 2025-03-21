import SwiftUI

struct TemplatesView: View {
    @StateObject private var viewModel = TemplatesViewModel()
    @Binding var selectedTemplate: Template?
    @State private var showAddTemplate = false
    @State private var showEditTemplate = false
    @State private var templateToEdit: Template?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Your Templates")) {
                    if viewModel.templates.isEmpty {
                        Text("No templates yet. Create your first template to get started.")
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        ForEach(viewModel.templates) { template in
                            TemplateRow(template: template)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTemplate = template
                                    presentationMode.wrappedValue.dismiss()
                                }
                                .contextMenu {
                                    Button(action: {
                                        selectedTemplate = template
                                        presentationMode.wrappedValue.dismiss()
                                    }) {
                                        Label("Use Template", systemImage: "checkmark.circle")
                                    }
                                    
                                    Button(action: {
                                        templateToEdit = template
                                        showEditTemplate = true
                                    }) {
                                        Label("Edit Template", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive, action: {
                                        viewModel.deleteTemplate(template)
                                    }) {
                                        Label("Delete Template", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            let templatesArr = Array(viewModel.templates)
                            for index in indexSet {
                                viewModel.deleteTemplate(templatesArr[index])
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddTemplate = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddTemplate) {
                TemplateFormView(onSave: { name, text, hashtags in
                    viewModel.addTemplate(name: name, text: text, hashtags: hashtags)
                })
            }
            .sheet(isPresented: $showEditTemplate, onDismiss: {
                templateToEdit = nil
            }) {
                if let template = templateToEdit {
                    TemplateFormView(
                        template: template,
                        onSave: { name, text, hashtags in
                            var updatedTemplate = template
                            updatedTemplate.name = name
                            updatedTemplate.text = text
                            updatedTemplate.hashtags = hashtags
                            viewModel.updateTemplate(updatedTemplate)
                            templateToEdit = nil
                        }
                    )
                }
            }
        }
    }
}

struct TemplateRow: View {
    let template: Template
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                .font(.headline)
            
            Text(template.text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            if !template.hashtags.isEmpty {
                Text(template.formattedHashtags)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TemplateFormView: View {
    let template: Template?
    let onSave: (String, String, [String]) -> Void
    
    @State private var name: String
    @State private var text: String
    @State private var hashtagsText: String
    @Environment(\.presentationMode) var presentationMode
    
    init(template: Template? = nil, onSave: @escaping (String, String, [String]) -> Void) {
        self.template = template
        self.onSave = onSave
        
        _name = State(initialValue: template?.name ?? "")
        _text = State(initialValue: template?.text ?? "")
        _hashtagsText = State(initialValue: template?.hashtags.joined(separator: " ") ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Template Details")) {
                    TextField("Template Name", text: $name)
                    
                    TextField("Post Text", text: $text, axis: .vertical)
                        .lineLimit(5...10)
                }
                
                Section(header: Text("Hashtags"), footer: Text("Enter hashtags separated by spaces (with or without # symbol)")) {
                    TextField("hashtag1 hashtag2 hashtag3", text: $hashtagsText, axis: .vertical)
                        .lineLimit(3...5)
                }
                
                Section {
                    Button("Save Template") {
                        saveTemplate()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(template == nil ? "Add Template" : "Edit Template")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func saveTemplate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else { return }
        
        // Process hashtags
        let hashtags = hashtagsText
            .split(separator: " ")
            .map { tag -> String in
                let tagString = String(tag)
                if tagString.hasPrefix("#") {
                    return String(tagString.dropFirst()) // Remove the # symbol
                }
                return tagString
            }
            .filter { !$0.isEmpty }
        
        onSave(trimmedName, trimmedText, hashtags)
        presentationMode.wrappedValue.dismiss()
    }
}

struct TemplatesView_Previews: PreviewProvider {
    static var previews: some View {
        TemplatesView(selectedTemplate: .constant(nil))
    }
} 