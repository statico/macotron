// Coerce.swift — one Any -> number conversion, shared by every module.
//
// Six near-identical helpers used to live one per module and none agreed on
// which inputs they took. This is their union: a Swift Int first so an exact
// integer never detours through Double, then NSNumber, which is what values
// out of a CFDictionary, an IOKit property or the JS bridge actually are --
// Int32, Int64, UInt64, Float, Double and Bool all bridge to it. Strings and
// everything else stay nil.
import Foundation

enum Coerce {
    static func int(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        return (value as? NSNumber)?.intValue
    }

    static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        return (value as? NSNumber)?.doubleValue
    }
}
