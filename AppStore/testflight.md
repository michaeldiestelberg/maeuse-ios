# TestFlight Information

TestFlight is strongly recommended before App Store submission, especially for microphone permission, Voice Mode, Keychain persistence, backup import/export, and real-device layout checks. Internal testing does not require Beta App Review; the first external build may.

## Feedback email

`m.diestelberg@gmail.com`

## English beta app description

Mäuse is a local-first shared-expense tracker for two people. Add expenses manually, split them by percentage or fixed partner amount, review monthly totals, and export or restore portable JSON backups. Optional Voice Mode can turn several spoken expenses into drafts using the tester’s OpenAI API project. Voice drafts are reviewed before they are saved.

## German beta app description

Mäuse ist ein lokaler Ausgaben-Tracker für zwei Personen. Erfasse Ausgaben manuell, teile sie prozentual oder mit einem festen Partnerbetrag, prüfe Monatssummen und exportiere oder importiere portable JSON-Backups. Der optionale Sprachmodus kann über das OpenAI-API-Projekt des Testers mehrere gesprochene Ausgaben in Entwürfe umwandeln. Sprachentwürfe werden vor dem Speichern geprüft.

## What to test — English

Please focus on these flows:

1. Complete onboarding and add, edit, and delete expenses.
2. Try percentage and fixed-amount splits; verify totals and partner shares.
3. Navigate between months and confirm empty states.
4. Export a JSON backup, add another expense, then import the backup. Confirm that the replacement warning is clear and that the restored values are correct.
5. Switch between English and German, and between light, dark, and system appearance.
6. Test without a network connection. Manual tracking and local backups should continue to work; Voice Mode should remain unavailable.
7. For Voice Mode, use a compatible OpenAI API project and key. Verify the key, review the disclosure, accept consent, and enable Voice Mode.
8. Dictate several expenses in one sentence. Review, remove, correct, and save drafts. Confirm that ending the session stops microphone use.
9. Disable Voice Mode, withdraw consent, remove the saved key, and verify that re-enabling requires consent again.
10. Test microphone allow, deny, and later-enable flows through iOS Settings.

Never include a real API key, private expense backup, or other secret in TestFlight feedback screenshots or comments.

## Was getestet werden soll — Deutsch

Bitte konzentriere dich auf diese Abläufe:

1. Schließe das Onboarding ab und erfasse, bearbeite und lösche Ausgaben.
2. Teste prozentuale Aufteilungen und feste Partnerbeträge; prüfe Summen und Partneranteile.
3. Wechsle zwischen Monaten und prüfe leere Zustände.
4. Exportiere ein JSON-Backup, füge eine weitere Ausgabe hinzu und importiere anschließend das Backup. Prüfe den Ersetzungshinweis und die wiederhergestellten Werte.
5. Wechsle zwischen Deutsch und Englisch sowie hellem, dunklem und systemweitem Erscheinungsbild.
6. Teste ohne Netzwerk. Manuelle Erfassung und lokale Backups sollen funktionieren; der Sprachmodus soll nicht verfügbar sein.
7. Nutze für den Sprachmodus ein kompatibles OpenAI-API-Projekt. Verifiziere den Schlüssel, lies den Datenschutzhinweis, stimme zu und aktiviere den Sprachmodus.
8. Diktiere mehrere Ausgaben in einem Satz. Prüfe, entferne, korrigiere und speichere Entwürfe. Das Beenden der Sitzung muss die Mikrofonnutzung stoppen.
9. Deaktiviere den Sprachmodus, widerrufe die Einwilligung, entferne den Schlüssel und prüfe, dass eine erneute Aktivierung wieder eine Einwilligung verlangt.
10. Teste Mikrofonzugriff erlauben, ablehnen und später über die iOS-Einstellungen aktivieren.

Gib niemals einen echten API-Schlüssel, ein privates Ausgaben-Backup oder andere Geheimnisse in TestFlight-Feedback und Screenshots ein.

## Beta App Review information

Use the same contact, temporary OpenAI review key, review steps, privacy URL, and support URL as `review-notes.md`. Add the temporary key only in App Store Connect, not to this file.
