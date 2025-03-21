import Foundation

class TemplateService {
    private let templateKey = "saved_templates"
    
    func saveTemplates(_ templates: [Template]) {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: templateKey)
        }
    }
    
    func loadTemplates() -> [Template] {
        if let data = UserDefaults.standard.data(forKey: templateKey),
           let templates = try? JSONDecoder().decode([Template].self, from: data) {
            return templates
        }
        return []
    }
    
    func saveTemplate(_ template: Template, templates: inout [Template]) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            var updatedTemplate = template
            updatedTemplate.updatedAt = Date()
            templates[index] = updatedTemplate
        } else {
            templates.append(template)
        }
        
        saveTemplates(templates)
    }
    
    func deleteTemplate(_ template: Template, templates: inout [Template]) {
        templates.removeAll { $0.id == template.id }
        saveTemplates(templates)
    }
} 