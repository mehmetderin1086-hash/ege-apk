import AlarmKit

/// Uygulama ile widget uzantısının paylaştığı alarm üst verisi.
nonisolated struct AsistanAlarmMeta: AlarmMetadata {
    var baslik: String
    init(baslik: String) { self.baslik = baslik }
}
