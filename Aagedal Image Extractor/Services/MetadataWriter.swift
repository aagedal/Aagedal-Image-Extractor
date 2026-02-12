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

            await progressHandler(Double(index + 1) / total)
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

        // Heading
        if let value = resolveField(configuration.heading, autoValue: configuration.heading.includeDocumentName ? documentFileName : nil) {
            args.append("-XMP-photoshop:Headline=\(value)")
            if !isJXL { args.append("-IPTC:Headline=\(value)") }
        }

        // Description
        if let value = resolveField(configuration.description, autoValue: configuration.description.includeDocumentName ? documentFileName : nil) {
            args.append("-XMP-dc:Description=\(value)")
            if !isJXL { args.append("-IPTC:Caption-Abstract=\(value)") }
        }

        // Copyright
        if let value = resolveField(configuration.copyright, autoValue: configuration.copyright.includeDocumentName ? documentFileName : nil) {
            args.append("-XMP-dc:Rights=\(value)")
            if !isJXL { args.append("-IPTC:CopyrightNotice=\(value)") }
        }

        // Keywords
        if let keywords = resolveKeywords(configuration.keywords, documentFileName: documentFileName) {
            args.append("-XMP-dc:Subject=")
            if !isJXL { args.append("-IPTC:Keywords=") }
            for keyword in keywords {
                args.append("-XMP-dc:Subject+=\(keyword)")
                if !isJXL { args.append("-IPTC:Keywords+=\(keyword)") }
            }
        }

        // Extended Description (XMP IPTC Core)
        if let value = resolveExtendedDescription(configuration.extendedDescription, documentFileName: documentFileName, pageNumber: pageNumber) {
            args.append("-XMP-iptcCore:ExtDescrAccessibility=\(value)")
        }

        // Only proceed if we have tags beyond -overwrite_original
        guard args.count > 1 else { return [] }

        args.append(fileURL.path)
        return args
    }

    // MARK: - Field Resolution

    nonisolated private func resolveField(
        _ config: MetadataFieldConfig,
        autoValue: String?
    ) -> String? {
        guard config.enabled else { return nil }

        let hasAuto = autoValue != nil && !autoValue!.isEmpty
        let customTrimmed = config.customText.trimmingCharacters(in: .whitespaces)
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

    nonisolated private func resolveKeywords(
        _ config: MetadataFieldConfig,
        documentFileName: String
    ) -> [String]? {
        guard config.enabled else { return nil }

        let hasDocName = config.includeDocumentName
        let customKeywords = config.customText
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
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

    nonisolated private func resolveExtendedDescription(
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
