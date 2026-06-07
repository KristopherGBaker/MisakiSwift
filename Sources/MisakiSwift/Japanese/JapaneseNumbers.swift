//
//  MisakiSwift — Japanese G2P
//
//  Compact integer → hiragana reading. CFStringTokenizer leaves Arabic numerals
//  untouched ("2024" stays "2024"), so JapaneseG2P converts them here before
//  phonemization. Covers 0 ..< 10^12 with the standard 千/百/十 sound changes
//  (さんびゃく, ろっぴゃく, はっせん …). Decimals, fractions, phone-number styles
//  and counter-specific readings are out of scope for Phase 1 (OpenJTalk handles
//  these natively in Phase 2).
//

enum JapaneseNumbers {
    private static let ones = ["", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]
    private static let juu = ["", "じゅう", "にじゅう", "さんじゅう", "よんじゅう",
                             "ごじゅう", "ろくじゅう", "ななじゅう", "はちじゅう", "きゅうじゅう"]
    private static let hyaku = ["", "ひゃく", "にひゃく", "さんびゃく", "よんひゃく",
                               "ごひゃく", "ろっぴゃく", "ななひゃく", "はっぴゃく", "きゅうひゃく"]
    private static let sen = ["", "せん", "にせん", "さんぜん", "よんせん",
                             "ごせん", "ろくせん", "ななせん", "はっせん", "きゅうせん"]

    static func hiragana(for value: Int) -> String {
        if value == 0 { return "ぜろ" }
        if value < 0 { return "マイナス" + hiragana(for: -value) }

        var result = ""
        var remainder = value

        let oku = remainder / 100_000_000
        remainder %= 100_000_000
        let man = remainder / 10_000
        remainder %= 10_000

        if oku > 0 { result += underTenThousand(oku) + "おく" }
        if man > 0 { result += underTenThousand(man) + "まん" }
        if remainder > 0 { result += underTenThousand(remainder) }
        return result
    }

    private static func underTenThousand(_ x: Int) -> String {
        sen[(x / 1000) % 10] + hyaku[(x / 100) % 10] + juu[(x / 10) % 10] + ones[x % 10]
    }
}
