# App Store Screenshot Set

For 1.4.0, scenes 01–04 are fresh captures from an isolated iPhone 18 Pro Max simulator running iOS 27, using synthetic data. Framed output is 1320×2868. Provide the same five scenes in English and German. Scene 05 is retained from 1.3.0 because the widget UI is unchanged.

## Order

1. `01-dashboard`
   - English caption: Separate accounts. One clear balance.
   - German caption: Getrennte Konten. Klare Bilanz.
   - Populated current-month dashboard with totals and realistic sample expenses.

2. `02-editor`
   - English caption: Add an expense in seconds.
   - German caption: In Sekunden eine Ausgabe erfassen.
   - New-expense sheet prefilled with groceries and a 50/50 split.

3. `03-voice`
   - English caption: Just say it. Review it. Save it.
   - German caption: Sagen. Prüfen. Speichern.
   - Voice workspace showing three recognized, reviewable expense drafts. No real microphone recording or API credential is used for the screenshot.

4. `04-settings`
   - English caption: Your expenses. Your control.
   - German caption: Eure Ausgaben. Eure Kontrolle.
   - Settings showing verified Voice Mode, the two Voice Mode toggles, backup controls, and privacy/support access. The visible API suffix is synthetic. Freshly captured for 1.4.0; consent is revoked by turning Voice Mode off.

5. `05-widgets`
   - English caption: Capture it before you forget.
   - German caption: Erfassen, bevor es vergessen ist.
   - Home Screen with both medium Mäuse widgets side by side — dictate on the left, manual add on the right — showing that a new expense starts without opening the app first. Capture on a stock Home Screen page with the widgets in the top row.
   - Note: the simulator has no Wallpaper pane, so the stock wallpaper is used. A solid brand-colour backdrop needs a capture from a physical device.

## Rules

- Use only synthetic sample expenses.
- Never show a complete API key.
- Keep status bars free of personal carrier or notification details.
- Do not use onboarding or a logo-only screen as the first screenshot.
- Screenshots must match the submitted build.
- Keep caption text outside the raw capture in the companion framed assets; raw captures remain available for review and fallback.
