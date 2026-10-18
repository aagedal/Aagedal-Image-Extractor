import Foundation

struct MetadataWriter {
    let exiftoolURL: URL

    func writeMetadata(
        to files: [URL],
        configuration: MetadataConfiguration,
        documentFileName: String,
        progressHandler: @MainActor (Double) -> Void
    ) async throws {
        let total = Double(files.count)

        for (index, file) in files.enumerated() {
            let pageNumber = Self.parsePageNumber(from: file.lastPathComponent)
            let args = buildArguments(
                for: file,
                configuration: configuration,
                documentFileName: documentFileName,
                pageNumber: pageNumber
            )

            if !args.isEmpty {
                let result = try await runProcess(
                    executableURL: exiftoolURL,
                    arguments: args
                )
                if result.exitCode != 0 {
                    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    // exiftool returns exit code 1 for minor warnings (e.g. JXL container wrapping)
                    // that don't indicate actual failure — check stdout for success confirmation
                    let isMinorWarning = stderr.contains("[minor]")
                        && result.stdout.contains("image files updated")
                    if !isMinorWarning {
                        throw AppError.metadataWriteFailed(
                            "\(file.lastPathComponent): \(stderr.isEmpty ? "exit code \(result.exitCode)" : stderr)"
                        )
                    }
                }
            }

            progressHandler(Double(index + 1) / total)
        }
    }

    // MARK: - Page Number Parsing

    nonisolated static func parsePageNumber(from filename: String) -> Int? {
        let pattern = #/_P(\d+)_I\d+\.[a-zA-Z]+$/#
        guard let match = filename.firstMatch(of: pattern) else { return nil }
        return Int(match.1)
    }

    // MARK: - Argument Building

    nonisolated private func buildArguments(
        for fileURL: URL,
        configuration: MetadataConfiguration,
        documentFileName: String,
        pageNumber: Int?
    ) -> [String] {
        let isJXL = fileURL.pathExtension.lowercased() == "jxl"
        var args: [String] = ["-overwrite_original"]

        let values = Self.resolve(configuration: configuration, documentFileName: documentFileName, pageNumber: pageNumber)

        // Heading
        if let value = values.heading {
            args.append("-XMP-photoshop:Headline=\(value)")
            if !isJXL { args.append("-IPTC:Headline=\(value)") }
        }

        // Description
        if let value = values.description {
            args.append("-XMP-dc:Description=\(value)")
            if !isJXL { args.append("-IPTC:Caption-Abstract=\(value)") }
        }

        // Copyright
        if let value = values.copyright {
            args.append("-XMP-dc:Rights=\(value)")
            if !isJXL { args.append("-IPTC:CopyrightNotice=\(value)") }
        }

        // Keywords
        if let keywords = values.keywords {
            // Repeated assignments replace a list. += can retain existing IPTC entries,
            // even when preceded by an empty assignment in the same invocation.
            for keyword in keywords {
                args.append("-XMP-dc:Subject=\(keyword)")
                if !isJXL { args.append("-IPTC:Keywords=\(keyword)") }
            }
        }

        // Extended Description (XMP IPTC Core)
        if let value = values.extendedDescription {
            args.append("-XMP-iptcCore:ExtDescrAccessibility=\(value)")
        }

        // Only proceed if we have tags beyond -overwrite_original
        guard args.count > 1 else { return [] }

        args.append(fileURL.path)
        return args
    }

    // The preview and ExifTool arguments use the same resolved values.
    struct ResolvedMetadata {
        let heading: String?
        let description: String?
        let copyright: String?
        let keywords: [String]?
        let extendedDescription: String?

        var previewFields: [(title: String, value: String)] {
            [
                ("Headline", heading),
                ("Description", description),
                ("Extended Description", extendedDescription),
                ("Keywords", keywords?.joined(separator: "; ")),
                ("Copyright", copyright),
            ].compactMap { title, value in value.map { (title: title, value: $0) } }
        }
    }

    nonisolated static func resolve(configuration: MetadataConfiguration, documentFileName: String, pageNumber: Int?) -> ResolvedMetadata {
        ResolvedMetadata(
            heading: resolveField(configuration.heading, autoValue: configuration.heading.includeDocumentName ? documentFileName : nil),
            description: resolveField(configuration.description, autoValue: configuration.description.includeDocumentName ? documentFileName : nil),
            copyright: resolveField(configuration.copyright, autoValue: configuration.copyright.includeDocumentName ? documentFileName : nil),
            keywords: resolveKeywords(configuration.keywords, documentFileName: documentFileName),
            extendedDescription: resolveExtendedDescription(configuration.extendedDescription, documentFileName: documentFileName, pageNumber: pageNumber)
        )
    }

    // MARK: - Field Resolution

    nonisolated private static func resolveField(
        _ config: MetadataFieldConfig,
        autoValue: String?
    ) -> String? {
        guard config.enabled else { return nil }

        let hasAuto = autoValue != nil && !autoValue!.isEmpty
        let customTrimmed = config.customText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustom = !customTrimmed.isEmpty

        if !hasAuto && !hasCustom { return nil }

        if hasAuto && hasCustom {
            switch config.textPlacement {
            case .prepend: return "\(customTrimmed) \(autoValue!)"
            case .append: return "\(autoValue!) \(customTrimmed)"
            }
        }

        if hasAuto && config.includeDocumentName { return autoValue! }
        if hasCustom { return customTrimmed }

        return nil
    }

    nonisolated private static func resolveKeywords(
        _ config: MetadataFieldConfig,
        documentFileName: String
    ) -> [String]? {
        guard config.enabled else { return nil }

        let hasDocName = config.includeDocumentName
        let customKeywords = config.customText
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !hasDocName && customKeywords.isEmpty { return nil }

        var result: [String] = []

        switch config.textPlacement {
        case .prepend:
            result.append(contentsOf: customKeywords)
            if hasDocName { result.append(documentFileName) }
        case .append:
            if hasDocName { result.append(documentFileName) }
            result.append(contentsOf: customKeywords)
        }

        return result.isEmpty ? nil : result
    }

    nonisolated private static func resolveExtendedDescription(
        _ config: MetadataFieldConfig,
        documentFileName: String,
        pageNumber: Int?
    ) -> String? {
        guard config.enabled else { return nil }

        var autoValue: String?
        if config.includeDocumentName {
            if let page = pageNumber {
                autoValue = "File name: \(documentFileName), Page: \(page)"
            } else {
                autoValue = "File name: \(documentFileName)"
            }
        }

        return resolveField(config, autoValue: autoValue)
    }
}
