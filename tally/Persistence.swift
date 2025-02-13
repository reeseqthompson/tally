//
//  Persistence.swift
//  tally
//
//  Created by Reese Thompson on 2/13/25.
//

import Foundation

// Returns the URL for the app's documents directory.
func getDocumentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}

// Saves any Encodable data to a file with the given filename.
func saveData<T: Encodable>(_ data: T, filename: String) {
    let url = getDocumentsDirectory().appendingPathComponent(filename)
    do {
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: url)
    } catch {
        print("Error saving \(filename): \(error)")
    }
}

// Loads and decodes data of type T from a file with the given filename.
func loadData<T: Decodable>(filename: String, as type: T.Type) -> T? {
    let url = getDocumentsDirectory().appendingPathComponent(filename)
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        print("Error loading \(filename): \(error)")
        return nil
    }
}

