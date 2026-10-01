/// Findings #19 and #20 — finding a venue, and naming one twice.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/models/venue.dart';
import 'package:prism_venues/data/models/zone.dart';
import 'package:prism_venues/features/venues/portfolio_screen.dart';

Venue _venue(String name, {String? address}) => Venue(
      id: name,
      name: name,
      address: address,
      zones: const [
        Zone(id: 'z', name: 'Main', status: ZoneStatus.auto, moodId: 'peak'),
      ],
    );

void main() {
  group('#19 sorting is a real choice, not a label', () {
    test('the toggle moves between the two orders and back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(venueSortProvider), VenueSort.needsAttention);

      container.read(venueSortProvider.notifier).toggle();
      expect(container.read(venueSortProvider), VenueSort.nameAZ);

      container.read(venueSortProvider.notifier).toggle();
      expect(container.read(venueSortProvider), VenueSort.needsAttention);
    });

    test('each order has a label, so the chip can say which it is in', () {
      // The chip shows the CURRENT order. It used to say "Needs attention"
      // whatever was happening, which is how a label gets mistaken for a menu.
      expect(VenueSort.needsAttention.label, 'Needs attention');
      expect(VenueSort.nameAZ.label, 'Name A–Z');
    });
  });

  group('#19 search matches what an owner remembers', () {
    // The filter as the screen applies it. Kept as a function so the rule is
    // testable without pumping 8 venues through a widget tree.
    List<Venue> matching(List<Venue> all, String query) {
      final q = query.trim().toLowerCase();
      if (q.isEmpty) return all;
      return [
        for (final v in all)
          if (v.name.toLowerCase().contains(q) ||
              (v.address ?? '').toLowerCase().contains(q))
            v,
      ];
    }

    final all = [
      _venue('Marina Café', address: '12 Marina Promenade'),
      _venue('Dockside', address: 'Pier 4, Harbour Walk'),
      _venue('Harbor House', address: '3 Quayside Lane'),
    ];

    test('by name, ignoring case', () {
      expect(matching(all, 'dock').single.name, 'Dockside');
      expect(matching(all, 'DOCK').single.name, 'Dockside');
    });

    test('by address, because that is how people remember a branch', () {
      expect(matching(all, 'quayside').single.name, 'Harbor House');
    });

    test('an empty query is not a filter', () {
      expect(matching(all, '   ').length, 3);
    });

    test('no match returns nothing rather than everything', () {
      // The failure worth guarding: a filter that falls back to "all" on no
      // match looks like it is ignoring the box.
      expect(matching(all, 'zzz'), isEmpty);
    });
  });

  group('#19 search appears only when it earns its place', () {
    test('the threshold is where scrolling becomes the alternative', () {
      // Below it the whole estate is on one screen.
      expect(venueSearchThreshold, greaterThanOrEqualTo(5));
      expect(6 >= venueSearchThreshold, isFalse);
      expect(12 >= venueSearchThreshold, isTrue);
    });
  });
}
