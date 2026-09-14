# TestFlight Information

TestFlight is strongly recommended before App Store submission, especially for microphone permission, Voice Mode, Keychain persistence, backup import/export, and real-device layout checks. Internal testing does not require Beta App Review; the first external build may.

## Build 42 focus

- Save should always read “Save” / “Speichern,” without a draft count.
- Expand the request history: entries should appear directly below the title, without a subtitle.
- The footer should show only the total. Adding, correcting, removing, and saving drafts should work as before.

### Build 42 — Deutsch

Der Sprachmodus ist aufgeräumter: „Speichern“ ohne Anzahl, der Anfrageverlauf ohne Unterüberschrift und unten nur noch die Gesamtsumme. Bitte Ausgaben hinzufügen, korrigieren, entfernen und speichern; der Verlauf soll erhalten bleiben und die Summe korrekt sein.

## Build 41 focus

- Expand “What I understood” after dictating multiple requests, then correct an amount or remove a draft. Earlier requests should remain in order, and new spoken requests should appear once.
- Collapse the section: only its title should remain, without a count or preview. Check English/German, larger text, and dark appearance.
- Entries should sound closer to your phrasing, including short corrections, while remaining interpretations rather than exact transcripts. Finish or cancel and reopen Voice Mode: the history should start empty.

### Build 41 — Deutsch

„So habe ich dich verstanden“ zeigt jetzt den Verlauf deiner Anfragen und Korrekturen. Diktiere mehrere Ausgaben, korrigiere einen Betrag und entferne einen Entwurf: Frühere Anfragen sollen erhalten bleiben. Zugeklappt bleibt nur die Überschrift sichtbar. Prüfe natürliche Formulierungen, größere Schrift und den Dunkelmodus. Der Verlauf zeigt sinngemäß Verstandenes, kein wortgetreues Transkript, und beginnt in jeder neuen Sitzung leer.

## Build 40 focus

- Speak quietly, then at normal volume: the mouse's bars should move noticeably more than the gentle idle wave and settle back during pauses.
- Check on a physical iPhone, including your usual microphone or headset. Dictation accuracy and saving expenses should remain unchanged.

### Build 40 — Deutsch

Sprich leise und anschließend mit normaler Lautstärke: Die Balken in der Maus sollen deutlich stärker ausschlagen als die sanfte Welle in Sprechpausen. Prüfe dies auf einem echten iPhone, auch mit deinem üblichen Mikrofon oder Headset. Das Verstehen und Speichern von Ausgaben soll unverändert funktionieren.

## Build 39 focus

- After the mouse appears, stay silent: its audio bars should continue a slow, subtle wave to show that the microphone is active. Speaking should produce stronger movement.
- Enable Reduce Motion and stay silent: the idle wave should stop. Dictating, correcting, and saving expenses should work as before.

## Build 38 focus

- Open Voice Mode and watch the cheese crumbs orbit while connecting, then transform into the mouse when microphone capture starts. Begin speaking after the mouse appears and the readiness haptic fires.
- Verify that audio bars react to your voice, the draft area stays in place, and no connection/listening labels or repeated dictation hint appear.
- Enable Reduce Motion: the cheese should remain still and crossfade to the mouse. Check VoiceOver status, larger text sizes, and readable connection errors.

## Build 37 focus

- Dictate three expenses together, then correct just one amount. Cards should keep their positions, highlight only real corrections, and update the total.
- Expand “What I understood” to read the latest request. Routine acknowledgments should not appear as chat bubbles.
- Dictate an expense without an amount, answer the clarification question, then remove a draft and save the rest.
- Check English/German, dark mode, and larger text sizes. Expenses remain unsaved until the save button is tapped.

## 1.3.1 focus — English

Voice Mode now uses GPT-Realtime-2.1 without a separate transcription model. On a real iPhone, dictate several expenses, then correct an amount or remove a draft. Check amounts, dates, partner shares, and the expandable “What I understood” summary before saving. The summary is an interpretation, not a word-for-word transcript. Try English and German, and report unclear speech or unusually slow responses.

## Schwerpunkt 1.3.1 — Deutsch

Der Sprachmodus nutzt jetzt GPT-Realtime-2.1 ohne separates Transkriptionsmodell. Diktiere auf einem echten iPhone mehrere Ausgaben, korrigiere anschließend einen Betrag oder entferne einen Entwurf. Prüfe vor dem Speichern Beträge, Daten, Partneranteile und die aufklappbare Zusammenfassung „So habe ich dich verstanden“. Diese zeigt die Interpretation, kein wortgetreues Transkript. Teste Deutsch und Englisch und melde unklar verstandene Sprache oder ungewöhnlich langsame Antworten.

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
9. Turn Voice Mode off, then on again, and verify that the disclosure reappears and consent must be accepted before it re-enables. Then remove the saved key.
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
