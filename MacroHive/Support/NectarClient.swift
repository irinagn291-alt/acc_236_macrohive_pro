import Foundation

struct OffSearchDTO: Decodable {
    let products: [OffProductDTO]?
}

struct OffProductResponseDTO: Decodable {
    let status: Int
    let product: OffProductDTO?
}

struct OffProductDTO: Decodable {
    let code: String?
    let productName: String?
    let genericName: String?
    let brands: String?
    let imageFrontSmallUrl: String?
    let imageSmallUrl: String?
    let imageUrl: String?
    let nutriments: OffNutrimentsDTO?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
        case imageFrontSmallUrl = "image_front_small_url"
        case imageSmallUrl = "image_small_url"
        case imageUrl = "image_url"
        case nutriments
    }

    func mapped(now: Int64 = Int64(Date().timeIntervalSince1970)) -> CombProduct? {
        let pickedName = [productName, genericName, brands]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let pickedName else { return nil }
        let rawCode = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawCode.isEmpty else { return nil }
        let barcode = CombBarcode.primary(from: rawCode) ?? rawCode
        let energyKcal = nutriments?.energyKcal100g?.value
        let energyKJ = nutriments?.energy100g?.value
        let image = [imageFrontSmallUrl, imageSmallUrl, imageUrl]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        return CombProduct(
            barcode: barcode,
            name: pickedName,
            brand: brands?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            kcal100: CombPortion.kcal100(energyKcal: energyKcal, energyKJ: energyKJ),
            protein100: nutriments?.proteins100g?.value,
            carbs100: nutriments?.carbohydrates100g?.value,
            fat100: nutriments?.fat100g?.value,
            imageURL: image,
            shelfAsset: CombShelf.product(barcode: barcode)?.shelfAsset,
            refreshedAt: now
        )
    }
}

struct OffNutrimentsDTO: Decodable {
    let energyKcal100g: OptionalNutrient?
    let energy100g: OptionalNutrient?
    let proteins100g: OptionalNutrient?
    let carbohydrates100g: OptionalNutrient?
    let fat100g: OptionalNutrient?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energy100g = "energy_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
    }
}

struct OptionalNutrient: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let number = try? container.decode(Double.self) {
            value = number
            return
        }
        if let number = try? container.decode(Int.self) {
            value = Double(number)
            return
        }
        if let raw = try? container.decode(String.self) {
            let normalised = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            value = Double(normalised)
            return
        }
        value = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum NectarError: Error, Equatable {
    case notFound
    case transport
    case decoding
    case missingEnergy
    case cancelled
}

enum CombPayload {
    static func decodeSearch(_ data: Data) throws -> [CombProduct] {
        do {
            let dto = try JSONDecoder().decode(OffSearchDTO.self, from: data)
            return (dto.products ?? []).compactMap { $0.mapped() }
        } catch is DecodingError {
            throw NectarError.decoding
        }
    }

    static func decodeProduct(_ data: Data) throws -> CombProduct {
        let dto: OffProductResponseDTO
        do {
            dto = try JSONDecoder().decode(OffProductResponseDTO.self, from: data)
        } catch is DecodingError {
            throw NectarError.decoding
        }
        if dto.status == 0 {
            throw NectarError.notFound
        }
        guard let product = dto.product?.mapped() else {
            throw NectarError.notFound
        }
        return product
    }
}

actor NectarClient {
    private let session: URLSession
    private let userAgent = "MacroHive/1.0 (iOS; +https://macrohive.pro)"

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = ["User-Agent": "MacroHive/1.0 (iOS; +https://macrohive.pro)"]
        self.session = URLSession(configuration: config)
    }

    func search(terms: String) async throws -> [CombProduct] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "16")
        ]
        guard let url = components?.url else { throw NectarError.transport }
        return try await fetch(url: url, map: CombPayload.decodeSearch)
    }

    func product(code: String) async throws -> CombProduct {
        guard let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(encoded).json") else {
            throw NectarError.transport
        }
        return try await fetch(url: url, map: CombPayload.decodeProduct)
    }

    private func fetch<T>(url: URL, map: (Data) throws -> T) async throws -> T {
        try await withRetry {
            var request = URLRequest(url: url)
            request.setValue("MacroHive/1.0 (iOS; +https://macrohive.pro)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NectarError.transport }
            if http.statusCode == 404 { throw NectarError.notFound }
            if (500...599).contains(http.statusCode) { throw NectarError.transport }
            guard http.statusCode == 200 else { throw NectarError.transport }
            return try map(data)
        }
    }

    private func withRetry<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch is CancellationError {
            throw NectarError.cancelled
        } catch NectarError.notFound {
            throw NectarError.notFound
        } catch NectarError.decoding {
            throw NectarError.decoding
        } catch {
            if Task.isCancelled { throw NectarError.cancelled }
            do {
                return try await work()
            } catch is CancellationError {
                throw NectarError.cancelled
            } catch {
                if Task.isCancelled { throw NectarError.cancelled }
                throw NectarError.transport
            }
        }
    }
}

actor CombImageNectar {
    func data(for urlString: String?) async -> Data? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("MacroHive/1.0 (iOS; +https://macrohive.pro)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
