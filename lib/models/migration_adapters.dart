import 'dart:typed_data';

import 'package:finamp/services/queue_service.dart';
import 'package:hive_ce/hive.dart';

import 'finamp_models.dart';
import 'jellyfin_models.dart';

/// This class exists to be extended by FinampStorableQueueInfo.  It allows the migration
/// adapter to be registered with hive using a separate type ID without conflict
/// while still returning a FinampStorableQueueInfo.
class FinampStorableQueueInfoLegacy {
  const FinampStorableQueueInfoLegacy();
}

class FinampStorableQueueInfoMigrationAdapter extends TypeAdapter<FinampStorableQueueInfoLegacy> {
  @override
  final typeId = 61;

  @override
  FinampStorableQueueInfoLegacy read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read()};
    final currentTrack = fields[1] as BaseItemId?;
    return FinampStorableQueueInfo(
      packedPreviousTracks: FinampStorableQueueInfo.packIds((fields[0] as List).cast<BaseItemId>()),
      packedCurrentTrack: currentTrack == null ? Uint8List(0) : FinampStorableQueueInfo.packIds([currentTrack]),
      currentTrackSeek: (fields[2] as num?)?.toInt(),
      packedNextUp: FinampStorableQueueInfo.packIds((fields[3] as List).cast<BaseItemId>()),
      packedQueue: FinampStorableQueueInfo.packIds((fields[4] as List).cast<BaseItemId>()),
      creation: (fields[5] as num).toInt(),
      sourceIndex: 0,
      sourceList: [fields[6] as QueueItemSource? ?? QueueService.savedQueueSource],
      trackSourceIndexes: Uint8List(0),
      packedShuffleOrder: null,
    );
  }

  @override
  void write(BinaryWriter writer, FinampStorableQueueInfoLegacy obj) {
    throw Exception("Attempted to write hive entry using migration adapter.");
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinampStorableQueueInfoMigrationAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}

/// This class is a placeholder for the removed FinampFeatureChipType enum.  It allows the
/// migration adapter to be registered with hive using a separate type ID without conflict.
class FinampFeatureChipTypeLegacy {
  const FinampFeatureChipTypeLegacy();
}

class FinampFeatureChipTypeMigrationAdapter extends TypeAdapter<FinampFeatureChipTypeLegacy> {
  @override
  final typeId = 74;

  @override
  FinampFeatureChipTypeLegacy read(BinaryReader reader) {
    // The legacy payload is a single enum index byte.
    reader.readByte();
    return const FinampFeatureChipTypeLegacy();
  }

  @override
  void write(BinaryWriter writer, FinampFeatureChipTypeLegacy obj) {
    throw Exception("Attempted to write hive entry using migration adapter.");
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinampFeatureChipTypeMigrationAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}

/// This class is a placeholder for the removed FinampFeatureChipsConfiguration class.  It allows the
/// migration adapter to be registered with hive using a separate type ID without conflict.
class FinampFeatureChipsConfigurationLegacy {
  const FinampFeatureChipsConfigurationLegacy();
}

class FinampFeatureChipsConfigurationMigrationAdapter extends TypeAdapter<FinampFeatureChipsConfigurationLegacy> {
  @override
  final typeId = 75;

  @override
  FinampFeatureChipsConfigurationLegacy read(BinaryReader reader) {
    // The legacy payload is a map of field indices to values (enabled, features, migrated).
    // The feature list elements are consumed by FinampFeatureChipTypeMigrationAdapter.
    final numOfFields = reader.readByte();
    for (int i = 0; i < numOfFields; i++) {
      reader.readByte();
      reader.read();
    }
    return const FinampFeatureChipsConfigurationLegacy();
  }

  @override
  void write(BinaryWriter writer, FinampFeatureChipsConfigurationLegacy obj) {
    throw Exception("Attempted to write hive entry using migration adapter.");
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinampFeatureChipsConfigurationMigrationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
