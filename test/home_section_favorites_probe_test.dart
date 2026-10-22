// Throwaway probe: verifies empty favorite-only home sections are hidden.
import 'dart:io';

import 'package:finamp/components/MusicScreen/sort_and_filter_row.dart';
import 'package:finamp/components/finamp_section_header.dart';
import 'package:finamp/components/HomeScreen/home_screen_content.dart';
import 'package:finamp/hive_registrar.g.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/models/theme_mode_adapter.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/music_providers.dart';
import 'package:finamp/services/music_screen_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/adapters.dart';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp("finamp_home_section_test");
    Hive.init(dir.path);
    Hive.registerAdapters();
    Hive.registerAdapter(ThemeModeAdapter());
    Hive.registerAdapter(ColorAdapter());
    Hive.registerAdapter(LocaleAdapter());
    final box = await Hive.openBox<FinampSettings>("FinampSettings");
    await box.put(
      "FinampSettings",
      FinampSettings(
        downloadLocations: [],
        downloadLocationsMap: {},
        tabSortBy: {},
        tabSortOrder: {},
        homeScreenConfiguration: DefaultSettings.homeScreenConfiguration,
        gridImageSize: DefaultSettings.gridImageSize,
        homeScreenImageSize: DefaultSettings.homeScreenImageSize,
        deviceId: "test-device",
      ),
    );
    GetIt.instance.registerSingleton<ProviderContainer>(ProviderContainer());
  });

  tearDownAll(() async {
    GetIt.instance.reset();
    await Hive.deleteBoxFromDisk("FinampSettings");
  });

  testWidgets("favorite-only section is hidden when it has no items", (tester) async {
    final section = HomeScreenSectionConfiguration(
      base: TabsHomeSection(libraryId: currentLibraryPlaceholder, contentType: ContentType.tracks),
      sortConfig: SortAndFilterConfiguration(
        sortBy: SortBy.random,
        sortOrder: SortOrder.ascending,
        filters: {ItemFilter(type: ItemFilterType.isFavorite)},
      ),
    );

    final playable = MusicScreenPlayable(
      tab: ContentType.tracks,
      library: currentLibraryPlaceholder,
      source: QueueItemSource.rawId(
        type: QueueItemSourceType.homeScreenSection,
        name: QueueItemSourceName(
          type: QueueItemSourceNameType.homeScreenSection,
          localizationParameter: "favoriteTracks",
          pretranslatedName: "Favorite Tracks",
        ),
        id: section.id,
      ),
      sortConfig: ResolvedSortConfig.skipResolving(section.sortConfig),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resolveSectionProvider(section).overrideWith((ref) async => playable),
          loadHomeSectionItemsProvider(request: playable, startIndex: 0, limit: homeScreenSectionItemLimit)
              .overrideWith((ref) async => <BaseItemDto>[]),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CustomScrollView(slivers: [HomeScreenSection(sectionInfo: section)]),
          ),
        ),
      ),
    );

    // Before the section content fetch resolves, the header is still visible.
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byType(FinampSectionHeader), findsOneWidget);

    // Once the (empty) content resolves, the whole section is hidden.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FinampSectionHeader), findsNothing);
  });
}
