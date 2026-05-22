// TemplateExchange — JSON import/export for saved templates.
//
// CloudKit-backed SwiftData cannot rely on unique constraints, so imports
// upsert manually by stable template UUID.

import Foundation
import SwiftData

public struct TemplateExchangeDocument: Codable, Sendable, Equatable {
    public var schema: String
    public var version: Int
    public var id: UUID
    public var title: String
    public var body: String
    public var hashtags: [String]
    public var updatedAt: Date

    public init(
        id: UUID,
        title: String,
        body: String,
        hashtags: [String],
        updatedAt: Date,
        schema: String = TemplateExchange.templateSchema,
        version: Int = TemplateExchange.currentVersion
    ) {
        self.schema = schema
        self.version = version
        self.id = id
        self.title = title
        self.body = body
        self.hashtags = hashtags
        self.updatedAt = updatedAt
    }

    @MainActor
    public init(template: Template) {
        self.init(
            id: template.id,
            title: template.title,
            body: template.body,
            hashtags: template.hashtags,
            updatedAt: template.updatedAt
        )
    }
}

public struct TemplateExchangeArchive: Codable, Sendable, Equatable {
    public var schema: String
    public var version: Int
    public var templates: [TemplateExchangeArchiveRecord]

    public init(
        templates: [TemplateExchangeDocument],
        schema: String = TemplateExchange.archiveSchema,
        version: Int = TemplateExchange.currentVersion
    ) {
        self.schema = schema
        self.version = version
        self.templates = templates.map(TemplateExchangeArchiveRecord.init(document:))
    }
}

public struct TemplateExchangeArchiveRecord: Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var body: String
    public var hashtags: [String]
    public var updatedAt: Date

    public init(
        id: UUID,
        title: String,
        body: String,
        hashtags: [String],
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.hashtags = hashtags
        self.updatedAt = updatedAt
    }

    fileprivate init(document: TemplateExchangeDocument) {
        self.init(
            id: document.id,
            title: document.title,
            body: document.body,
            hashtags: document.hashtags,
            updatedAt: document.updatedAt
        )
    }
}

public enum TemplateExchangeError: Error, Sendable, LocalizedError {
    case encodingFailed(String)
    case invalidPayload(String)
    case unsupportedSchema(String)
    case unsupportedVersion(Int)
    case missingRequiredField(String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let reason):
            return "Could not encode template JSON: \(reason)"
        case .invalidPayload(let reason):
            return "Could not read template JSON: \(reason)"
        case .unsupportedSchema(let schema):
            return "Unsupported template exchange schema: \(schema)"
        case .unsupportedVersion(let version):
            return "Unsupported template exchange version: \(version)"
        case .missingRequiredField(let field):
            return "Template exchange JSON is missing a valid \(field)."
        }
    }
}

public enum TemplateExchange {
    public static let templateSchema = "com.tolbnet.BlueSkyTemplates.template"
    public static let archiveSchema = "com.tolbnet.BlueSkyTemplates.templateArchive"
    public static let currentVersion = 1

    public static func encode(_ document: TemplateExchangeDocument) throws -> Data {
        let validated = try document.validated()
        do {
            return try makeEncoder().encode(validated)
        } catch {
            throw TemplateExchangeError.encodingFailed(error.localizedDescription)
        }
    }

    public static func encode(_ archive: TemplateExchangeArchive) throws -> Data {
        let validated = try archive.validated()
        do {
            return try makeEncoder().encode(validated)
        } catch {
            throw TemplateExchangeError.encodingFailed(error.localizedDescription)
        }
    }

    @MainActor
    public static func encode(template: Template) throws -> Data {
        try encode(TemplateExchangeDocument(template: template))
    }

    public static func decodeTemplate(from data: Data) throws -> TemplateExchangeDocument {
        let header = try decodeHeader(from: data)
        guard header.schema == templateSchema else {
            throw TemplateExchangeError.unsupportedSchema(header.schema)
        }

        do {
            return try makeDecoder()
                .decode(TemplateExchangeDocument.self, from: data)
                .validated()
        } catch let error as TemplateExchangeError {
            throw error
        } catch {
            throw TemplateExchangeError.invalidPayload(error.localizedDescription)
        }
    }

    public static func decodeTemplates(from data: Data) throws -> [TemplateExchangeDocument] {
        let header = try decodeHeader(from: data)
        switch header.schema {
        case templateSchema:
            return [try decodeTemplate(from: data)]
        case archiveSchema:
            do {
                let archive = try makeDecoder()
                    .decode(TemplateExchangeArchive.self, from: data)
                    .validated()
                return try archive.templates.map { record in
                    try TemplateExchangeDocument(record: record).validated()
                }
            } catch let error as TemplateExchangeError {
                throw error
            } catch {
                throw TemplateExchangeError.invalidPayload(error.localizedDescription)
            }
        default:
            throw TemplateExchangeError.unsupportedSchema(header.schema)
        }
    }

    @MainActor
    @discardableResult
    public static func upsert(
        _ document: TemplateExchangeDocument,
        into context: ModelContext
    ) throws -> Template {
        let document = try document.validated()
        let id = document.id
        let descriptor = FetchDescriptor<Template>(
            predicate: #Predicate<Template> { template in
                template.id == id
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let matches = try context.fetch(descriptor)
        let template: Template

        if let existing = matches.first {
            template = existing
            for duplicate in matches.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            template = Template(
                id: document.id,
                title: document.title,
                body: document.body,
                hashtags: document.hashtags,
                updatedAt: document.updatedAt
            )
            context.insert(template)
        }

        apply(document, to: template)
        try context.save()
        return template
    }

    @MainActor
    @discardableResult
    public static func upsert(from data: Data, into context: ModelContext) throws -> [Template] {
        let documents = try decodeTemplates(from: data)
        return try documents.map { document in
            try upsert(document, into: context)
        }
    }
}

private struct TemplateExchangeHeader: Decodable {
    let schema: String
    let version: Int
}

private extension TemplateExchange {
    static func decodeHeader(from data: Data) throws -> TemplateExchangeHeader {
        do {
            let header = try makeDecoder().decode(TemplateExchangeHeader.self, from: data)
            guard header.version == currentVersion else {
                throw TemplateExchangeError.unsupportedVersion(header.version)
            }
            return header
        } catch let error as TemplateExchangeError {
            throw error
        } catch {
            throw TemplateExchangeError.invalidPayload(error.localizedDescription)
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601String(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = date(fromISO8601String: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 date string."
            )
        }
        return decoder
    }

    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(fromISO8601String raw: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    @MainActor
    static func apply(_ document: TemplateExchangeDocument, to template: Template) {
        template.id = document.id
        template.title = document.title
        template.body = document.body
        template.hashtags = document.hashtags
        template.updatedAt = document.updatedAt
    }
}

private extension TemplateExchangeDocument {
    init(record: TemplateExchangeArchiveRecord) {
        self.init(
            id: record.id,
            title: record.title,
            body: record.body,
            hashtags: record.hashtags,
            updatedAt: record.updatedAt
        )
    }

    func validated() throws -> Self {
        guard schema == TemplateExchange.templateSchema else {
            throw TemplateExchangeError.unsupportedSchema(schema)
        }
        guard version == TemplateExchange.currentVersion else {
            throw TemplateExchangeError.unsupportedVersion(version)
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TemplateExchangeError.missingRequiredField("title")
        }
        return self
    }
}

private extension TemplateExchangeArchive {
    func validated() throws -> Self {
        guard schema == TemplateExchange.archiveSchema else {
            throw TemplateExchangeError.unsupportedSchema(schema)
        }
        guard version == TemplateExchange.currentVersion else {
            throw TemplateExchangeError.unsupportedVersion(version)
        }
        return self
    }
}
