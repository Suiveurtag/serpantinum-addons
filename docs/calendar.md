# Calendar

Google Calendar (read/write) and iCal subscriptions (read only) in the clock panel and its agenda.

## Pieces

| Piece | Role |
| --- | --- |
| `scripts/gcal/gcal.py` | Backend, standard library only. OAuth, sync, edits, offline queue, reminders. Every command prints one JSON line. |
| `serpantinum-gcal.service` | User service running `gcal.py daemon`: sync every 5 min, replays queued edits every minute while some are pending, reminder notifications every 20 s. |
| `~/.local/state/serpantinum/gcal/` (0700) | `state.json` (what the shell reads), `store.json` (private cache, queue, prefs), `access.json` (short-lived access token). |
| Keyring (`secret-tool`, service `serpantinum-gcal`) | Refresh token, client ID and secret. Falls back to `secrets.json` (0600) when no keyring answers. |
| `payload/gcal/` → `quickshell/gcal/` | QML: `GCal` singleton (state + actions), `GCalLayer` (mounted in the clock panel), the agenda and its views. |
| `agenda.py` | Installer hooks (marked `serpantinum-gcal-v2` blocks), the Super+G and Super+I binds and the service. |

The shell never touches the network: it watches `state.json` and runs `gcal.py <command>` for every action.
Edits are written to the cache first (the UI updates at once, with a sweeping *pending* sheen) and sent to Google
right after; offline, they wait in the queue and the daemon replays them in order.

## Connecting Google

Google requires an OAuth client of your own (free). Settings → Calendar (`serpantinum settings addon_calendar`, also the agenda's gear button) links every step:

1. Create a project in Google Cloud.
2. Enable the **Google Calendar API**.
3. Set up the consent screen: audience **External**, add yourself, then **Publish app**. An app left in *Testing*
   gets refresh tokens that expire after 7 days; a published personal app shows an "unverified app" warning once,
   which you can accept (Advanced → continue).
4. Create an **OAuth client ID** of type **Desktop app** and paste its client ID and secret in the agenda.

*Connect* opens the browser on Google's consent page and listens on `127.0.0.1` (random port, PKCE) for the answer.
Scopes: `openid email https://www.googleapis.com/auth/calendar`. *Disconnect* revokes the token and clears the keyring.

## Repeating events

The event editor offers quick presets (every day, every weekday, weekends, every week, every 2 weeks, every month, every year)
and **Custom…**, which opens the advanced repeat editor:

- **Every N** days, weeks, months or years.
- **Weekly**: any set of weekdays (`BYDAY=MO,WE,FR`).
- **Monthly**: the start's day, specific days of the month (`1, 15`, or *last*), a weekday of the month (*1st, 2nd, 3rd, 4th or last Tuesday*)
  or the last weekday (`BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1`).
- **Yearly**: one or several months, with the same day patterns.
- **Ends**: never, on a date (`UNTIL`, written as a date for an all-day event and in UTC otherwise) or after N occurrences (`COUNT`).

Editing a recurring event keeps its `EXDATE` lines, and a rule written elsewhere is shown and edited as far as the editor understands
it: the parts it does not know (`WKST`, `BYWEEKNO`...) are kept as they are. Picking another unit starts a fresh pattern for that unit.

## iCal subscriptions

Any `http(s)://` or `webcal://` address of a `.ics` feed (Google's *secret address in iCal format*, Outlook,
iCloud public calendars, school timetables, holidays). They are fetched at each sync and are read only.
Supported: `RRULE` with `FREQ` daily/weekly/monthly/yearly, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY` (including
`2MO`, `-1FR`), `BYMONTHDAY`, `BYMONTH`, `BYSETPOS`, `WKST`, plus `EXDATE`, `RECURRENCE-ID` overrides, `TZID` and all-day events.

## Commands

```sh
GCAL=~/.local/share/serpantinum-addons-v2/scripts/gcal/gcal.py
python3 $GCAL status                 # account, calendars, counts (no event bodies)
python3 $GCAL sync                   # sync now
python3 $GCAL ics-add '{"url": "webcal://example.org/cal.ics", "name": "Holidays"}'
python3 $GCAL prefs '{"reminders": false}'
systemctl --user status serpantinum-gcal
journalctl --user -u serpantinum-gcal -f
```

IPC: `quickshell -p ~/.local/share/serpantinum/src/quickshell/Shell.qml ipc call addonCalendar toggle`
(`open`, `newEvent`, `sync`, `openEvent <id>`).

## Troubleshooting

- **"Google access was revoked or expired"**: the app is still in *Testing* (7-day tokens) or access was removed
  in your Google account. Publish the app, then Disconnect and Connect again.
- **"Google did not return a refresh token"**: remove the app from https://myaccount.google.com/permissions and
  connect again (Google only sends one on a fresh consent).
- **Nothing in the panel**: check `systemctl --user status serpantinum-gcal` and `python3 $GCAL status`.
- **Wrong times**: the backend uses `/etc/localtime` (or `TZ`) for new events; existing events keep their own zone.

## Tests

```sh
python3 -m unittest discover -s tests -p "test_gcal.py" -v     # backend: iCal, recurrence, queue, reminders
python3 -m unittest discover -s tests -p "test_agenda.py" -v   # installer hooks round trip
```
