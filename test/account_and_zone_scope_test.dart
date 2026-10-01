/// Findings #17 (no account screen) and #10 (which zone is this setting for?).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/roles.dart';
import 'package:prism_venues/data/models/guardrails.dart';
import 'package:prism_venues/data/models/user.dart';
import 'package:prism_venues/data/mock/mock_settings_repo.dart';
import 'package:prism_venues/data/mock/mock_auth_repo.dart';

void main() {
  group('#17 the account can be identified and its password changed', () {
    test('the signed-in user carries the address they signed in with', () {
      // The account screen could not say which account it was showing, because
      // the user payload had no email in it at all.
      const user = User(
        id: 'u1',
        name: 'Priya Nair',
        role: Role.manager,
        initials: 'PN',
        avatarColor: Color(0xFF84C44A),
        email: 'priya@marinacafe.com',
      );

      expect(user.email, 'priya@marinacafe.com');
    });

    test('an older server sending no email leaves it null, not blank', () {
      // The row falls back to the display name rather than showing an empty
      // value, so a missing field never reads as "no account".
      const user = User(
        id: 'u1',
        name: 'Priya Nair',
        role: Role.manager,
        initials: 'PN',
        avatarColor: Color(0xFF84C44A),
      );

      expect(user.email, isNull);
    });

    test('a wrong current password is refused, not silently accepted', () async {
      // The server really re-authenticates. A venue iPad sits unlocked on a
      // counter, so a bearer token alone must not be enough to take an account
      // from its owner.
      final repo = MockAuthRepo();

      expect(
        () => repo.changePassword(
          currentPassword: 'wrong',
          newPassword: 'a-good-password',
        ),
        throwsA(isA<Object>()),
      );
    });

    test('the right current password goes through', () async {
      final repo = MockAuthRepo();

      await expectLater(
        repo.changePassword(
          currentPassword: 'hunter22',
          newPassword: 'a-good-password',
        ),
        completes,
      );
    });
  });

  group('#10 a setting knows which zone it belongs to', () {
    test('apply-to-all writes every zone in the venue, not just this one',
        () async {
      // The Settings page is headed with the VENUE while the volume band is
      // stored per ZONE, so an owner changed the band believing it covered the
      // venue. This is the control that makes that belief true when they mean
      // it.
      final repo = MockSettingsRepo();
      const band = Guardrails(volumeMin: 10, volumeMax: 40);

      await repo.applyGuardrailsToVenue(
        'venue-1',
        ['zone-a', 'zone-b', 'zone-c'],
        band,
      );

      for (final zone in ['zone-a', 'zone-b', 'zone-c']) {
        expect(repo.guardrailsForZone(zone)?.volumeMax, 40,
            reason: '$zone should have the copied band');
      }
    });

    test('applying to no zones writes nothing rather than everything',
        () async {
      final repo = MockSettingsRepo();

      await repo.applyGuardrailsToVenue('venue-1', const [], const Guardrails());

      expect(repo.guardrailsForZone('zone-a'), isNull);
    });
  });
}
