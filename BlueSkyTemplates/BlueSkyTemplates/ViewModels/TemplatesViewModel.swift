import Foundation
import SwiftUI

class TemplatesViewModel: ObservableObject {
    @Published var templates: [Template] = []
    private let templateService = TemplateService()
    
    init() {
        loadTemplates()
    }
    
    func loadTemplates() {
        templates = templateService.loadTemplates()
        
        // Add sample templates if there are none
        if templates.isEmpty {
            templates = [Template.example, Template.cameraExample]
            templateService.saveTemplates(templates)
        }
    }
    
    func addTemplate(name: String, text: String, hashtags: [String]) {
        let newTemplate = Template(
            name: name,
            text: text,
            hashtags: hashtags
        )
        
        templates.append(newTemplate)
        templateService.saveTemplates(templates)
    }
    
    func updateTemplate(_ template: Template) {
        templateService.saveTemplate(template, templates: &templates)
    }
    
    func deleteTemplate(_ template: Template) {
        templateService.deleteTemplate(template, templates: &templates)
    }
    
    func findTemplateById(_ id: UUID) -> Template? {
        return templates.first { $0.id == id }
    }
    
    // Format tags from a string into an array of hashtags
    func formatTags(from text: String) -> [String] {
        // Split the text by spaces and filter for hashtags
        return text.split(separator: " ")
            .compactMap { tag -> String? in
                let tagString = String(tag)
                if tagString.hasPrefix("#") {
                    return String(tagString.dropFirst()) // Remove the # symbol
                }
                return tagString
            }
    }
} 