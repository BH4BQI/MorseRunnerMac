//
//  Stations.swift
//  Port of StnColl.pas — TStations.
//
//  Holds the active stations (DX callers + QRM/QRN interferers) and provides
//  factory methods for adding each kind.
//

import Foundation

public final class Stations {
    public private(set) var items: [Station] = []

    public var count: Int { items.count }
    public subscript(index: Int) -> Station {
        get { items[index] }
        set { items[index] = newValue }
    }

    public func clear() { items.removeAll() }

    public func remove(_ station: Station) {
        if let i = items.firstIndex(where: { $0 === station }) {
            items.remove(at: i)
        }
    }

    @discardableResult
    public func addCaller() -> Station {
        let s = DxStation()
        items.append(s)
        return s
    }

    @discardableResult
    public func addQrn() -> Station {
        let s = QrnStation()
        items.append(s)
        return s
    }

    @discardableResult
    public func addQrm() -> Station {
        let s = QrmStation()
        items.append(s)
        return s
    }
}
