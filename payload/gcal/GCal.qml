pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Calendar data for the clock panel and the agenda. Reads the backend's state.json (one inotify watch) and runs
// scripts/gcal/gcal.py for every action; the backend applies edits optimistically, so the UI updates on the next
// file change without waiting for Google.
QtObject {
    id: root

    readonly property string backend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/gcal/gcal.py"

    // Settings → Calendar → Enable. Off: no clock-panel hooks, no agenda, no sync, and the daemon is stopped.
    readonly property bool enabled: Config.getSetting("addonsV2Calendar", true) !== false
    readonly property bool reducedMotion: !!Config.getSetting("general", {}).performance
    readonly property bool previewEnabled: Config.getSetting("addonsV2CalendarPreview", true) !== false
    function setPreviewEnabled(on) { Config.setSetting("addonsV2CalendarPreview", on); }
    // Event badge under the clock: "never", "ahead" (starts within chipHours) or "ongoing" (only while it runs).
    readonly property string chipMode: Config.getSetting("addonsV2CalendarChipMode", "ahead")
    readonly property real chipHours: Number(Config.getSetting("addonsV2CalendarChipHours", 24)) || 24
    function setChipMode(m) { Config.setSetting("addonsV2CalendarChipMode", m); }
    function setChipHours(h) { Config.setSetting("addonsV2CalendarChipHours", h); }
    readonly property string unit: "serpantinum-gcal.service"
    function setEnabled(on) {
        Config.setSetting("addonsV2Calendar", on);
        if (!on) { root.agendaOpen = false; root.selectedDay = null; }
    }
    // Settings load after the shell starts, so react to the flag changing too.
    onEnabledChanged: Quickshell.execDetached(["systemctl", "--user", root.enabled ? "start" : "stop", root.unit])
    Component.onCompleted: if (!root.enabled) Quickshell.execDetached(["systemctl", "--user", "stop", root.unit])

    property var state: null
    property double now: Date.now()
    readonly property double todayStart: root.startOfDay(root.now).getTime()
    readonly property var today: new Date(root.todayStart)

    // UI state shared by the clock panel and the agenda.
    property bool agendaOpen: false
    property var focusDate: today          // day the agenda is centred on
    property var selectedDay: null         // day picked in the clock panel's mini calendar (null = today)
    property string agendaView: "week"     // month | week | day | list
    property string openEventId: ""        // event to reveal when the agenda opens
    property string lastError: ""
    property string connectError: ""
    property bool browserOpenFailed: false
    property int busy: 0

    readonly property string status: state ? state.status : "disconnected"
    readonly property bool google: !!(state && state.google)
    readonly property string account: google ? (state.google.email || "") : ""
    readonly property var calendars: state && state.calendars ? state.calendars : []
    readonly property var colors: state && state.colors ? state.colors : ({})
    readonly property var prefs: state && state.prefs ? state.prefs : ({ hidden: [], reminders: true, defaultCalendar: "", weekStart: 1 })
    readonly property var icsSources: state && state.ics ? state.ics : []
    readonly property bool available: calendars.length > 0
    readonly property bool syncing: !!(state && state.syncing) || busy > 0
    readonly property int pending: state ? (state.pending || 0) : 0
    readonly property string error: lastError || (state ? (state.error || "") : "")
    readonly property string authUrl: state ? (state.authUrl || "") : ""
    onAuthUrlChanged: if (authUrl && connectProc && !connectProc.cancelRequested) openAuthBrowser()
    readonly property var range: state && state.range ? state.range : ({ from: 0, to: 0 })

    readonly property var calendarMap: {
        const map = {};
        for (const c of root.calendars) map[c.id] = c;
        return map;
    }
    readonly property var writableCalendars: calendars.filter(c => c.writable)
    readonly property string defaultCalendar: {
        const wanted = root.prefs.defaultCalendar;
        if (wanted && root.calendarMap[wanted] && root.calendarMap[wanted].writable) return wanted;
        const primary = root.writableCalendars.find(c => c.primary);
        return primary ? primary.id : (root.writableCalendars.length ? root.writableCalendars[0].id : "");
    }

    readonly property var events: {
        const all = state && state.events ? state.events : [];
        return all.filter(e => {
            const cal = root.calendarMap[e.calendarId];
            return cal ? cal.visible !== false : true;
        });
    }

    // dayKey → events touching that day (multi-day events are listed on every day they cover).
    readonly property var dayIndex: {
        const index = {};
        for (const e of root.events) {
            const start = new Date(e.start);
            let cursor = new Date(start.getFullYear(), start.getMonth(), start.getDate());
            const last = e.end > e.start ? new Date(e.end - 1) : start;
            let guard = 0;
            while (cursor <= last && guard++ < 400) {
                const k = root.key(cursor);
                (index[k] = index[k] || []).push(e);
                cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1);
            }
        }
        for (const k in index) index[k].sort((a, b) => (b.allDay - a.allDay) || (a.start - b.start) || (b.end - a.end));
        return index;
    }

    // First event that is happening now or starts next (timed events, not declined), within the chosen window.
    readonly property var nextEvent: {
        let best = null;
        if (!root.enabled || root.chipMode === "never") return best;
        const ongoingOnly = root.chipMode === "ongoing";
        const limit = ongoingOnly ? root.now : root.now + root.chipHours * 3600000;
        for (const e of root.events) {
            if (e.allDay || e.rsvp === "declined" || e.end <= root.now || e.start > limit) continue;
            if (!best || e.start < best.start) best = e;
        }
        return best;
    }

    // ------------------------------------------------------------------ helpers

    function tr(en, fr) { return I18n.currentLang === "fr" && fr ? fr : en; }
    function key(d) {
        const date = d instanceof Date ? d : new Date(d);
        return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate();
    }
    function sameDay(a, b) { return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
    function startOfDay(d) { const x = new Date(d); return new Date(x.getFullYear(), x.getMonth(), x.getDate()); }
    function addDays(d, n) { const x = new Date(d); return new Date(x.getFullYear(), x.getMonth(), x.getDate() + n, x.getHours(), x.getMinutes()); }
    function addMonths(d, n) { const x = new Date(d); return new Date(x.getFullYear(), x.getMonth() + n, 1); }
    function weekStart(d) {
        const x = root.startOfDay(d);
        const first = root.prefs.weekStart === 0 ? 0 : 1;
        const shift = (x.getDay() - first + 7) % 7;
        return root.addDays(x, -shift);
    }
    function eventsOn(d) { return root.dayIndex[root.key(d)] || []; }
    function find(id) {
        const all = state && state.events ? state.events : [];
        return all.find(e => e.id === id) || null;
    }
    function colorOf(e) {
        if (!e) return ThemeBackend.blue;
        if (e.colorId && root.colors[e.colorId]) return root.colors[e.colorId];
        const cal = root.calendarMap[e.calendarId];
        return cal && cal.color ? cal.color : ThemeBackend.blue;
    }
    function dayColors(d) {
        const out = [];
        if (!root.enabled) return out;
        for (const e of root.eventsOn(d)) {
            const c = String(root.colorOf(e));
            if (out.indexOf(c) === -1) out.push(c);
            if (out.length === 3) break;
        }
        return out;
    }

    readonly property var locale: Qt.locale(I18n.qtLocaleName)
    readonly property string clockFormat: DateTime.timeFormat.replace(/[:.]s{1,2}/, "")
    function fmtTime(ms) { return DateTime.format(root.clockFormat, new Date(ms)); }
    function fmtRange(e) {
        if (!e) return "";
        if (e.allDay) {
            const days = Math.round((e.end - e.start) / 86400000);
            return days > 1 ? root.tr("All day · %1 days", "Toute la journée · %1 jours").arg(days) : root.tr("All day", "Toute la journée");
        }
        return root.fmtTime(e.start) + " – " + root.fmtTime(e.end);
    }
    function fmtDuration(minutes) {
        minutes = Math.max(0, Math.round(minutes));
        if (minutes < 60) return minutes + " min";
        const h = Math.floor(minutes / 60), m = minutes % 60;
        if (h >= 24) { const d = Math.round(h / 24); return d + root.tr(" d", " j"); }
        return m ? h + " h " + (m < 10 ? "0" : "") + m : h + " h";
    }
    // "in 25 min", "now · 20 min left", "tomorrow 09:00"
    function relative(e) {
        if (!e) return "";
        const mins = (e.start - root.now) / 60000;
        if (mins <= 0) return root.tr("now · %1 left", "en cours · encore %1").arg(root.fmtDuration((e.end - root.now) / 60000));
        if (mins < 60 * 12) return root.tr("in %1", "dans %1").arg(root.fmtDuration(Math.ceil(mins)));
        const day = root.startOfDay(e.start);
        const diff = Math.round((day - root.today) / 86400000);
        if (diff === 0) return root.tr("today %1", "aujourd'hui %1").arg(root.fmtTime(e.start));
        if (diff === 1) return root.tr("tomorrow %1", "demain %1").arg(root.fmtTime(e.start));
        return root.locale.dayName(day.getDay(), Locale.ShortFormat) + " " + root.fmtTime(e.start);
    }
    function dayTitle(d) {
        const diff = Math.round((root.startOfDay(d) - root.today) / 86400000);
        if (diff === 0) return root.tr("Today", "Aujourd'hui");
        if (diff === 1) return root.tr("Tomorrow", "Demain");
        if (diff === -1) return root.tr("Yesterday", "Hier");
        const name = root.locale.dayName(d.getDay(), Locale.LongFormat);
        return name.charAt(0).toUpperCase() + name.slice(1);
    }
    function monthTitle(d) {
        const name = root.locale.standaloneMonthName(d.getMonth(), Locale.LongFormat);
        return name.charAt(0).toUpperCase() + name.slice(1) + " " + d.getFullYear();
    }
    function shortDate(d) { return new Date(d).toLocaleDateString(root.locale, "ddd d MMM"); }
    function weekdayLetters() {
        const out = [];
        const first = root.prefs.weekStart === 0 ? 0 : 1;
        for (let i = 0; i < 7; i++) {
            const n = root.locale.dayName((first + i) % 7, Locale.ShortFormat);
            out.push(n.charAt(0).toUpperCase() + n.slice(1, 3).replace(".", ""));
        }
        return out;
    }
    // Recurrence: quick presets, an editable model of any RRULE (parseRule / buildRule) and a readable summary.
    readonly property var repeatPresets: [
        { id: "none", label: root.tr("Does not repeat", "Ne se répète pas"), rule: "" },
        { id: "daily", label: root.tr("Every day", "Tous les jours"), rule: "RRULE:FREQ=DAILY" },
        { id: "weekdays", label: root.tr("Every weekday", "Du lundi au vendredi"), rule: "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" },
        { id: "weekends", label: root.tr("Weekends", "Le week-end"), rule: "RRULE:FREQ=WEEKLY;BYDAY=SA,SU" },
        { id: "weekly", label: root.tr("Every week", "Toutes les semaines"), rule: "RRULE:FREQ=WEEKLY" },
        { id: "biweekly", label: root.tr("Every 2 weeks", "Toutes les 2 semaines"), rule: "RRULE:FREQ=WEEKLY;INTERVAL=2" },
        { id: "monthly", label: root.tr("Every month", "Tous les mois"), rule: "RRULE:FREQ=MONTHLY" },
        { id: "yearly", label: root.tr("Every year", "Tous les ans"), rule: "RRULE:FREQ=YEARLY" }
    ]
    readonly property var weekCodes: ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]      // index = Date.getDay()
    readonly property var weekOrder: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]      // order used in a written rule
    function ruleOf(list) {
        for (const line of (list || [])) if (String(line).indexOf("RRULE:") === 0) return String(line);
        return "";
    }
    // BEGIN rule model (pure functions, exercised by tests/test_gcal.py)
    // Swaps the RRULE line of a recurrence list, keeping its EXDATE / RDATE lines.
    function withRule(list, rule) {
        const rest = (list || []).filter(l => String(l).indexOf("RRULE:") !== 0);
        return rule ? [rule].concat(rest) : rest;
    }
    // UNTIL is a UTC date-time for a timed event and a plain date for an all-day one.
    function untilDay(v) {
        const m = String(v).match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?/);
        if (!m) return 0;
        if (m[7]) { const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }
        return new Date(+m[1], +m[2] - 1, +m[3]).getTime();
    }
    function untilString(dayMs, allDay) {
        const d = new Date(dayMs), pad = n => (n < 10 ? "0" : "") + n;
        if (allDay) return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate());
        const e = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59);
        return e.getUTCFullYear() + pad(e.getUTCMonth() + 1) + pad(e.getUTCDate()) + "T" + pad(e.getUTCHours()) + pad(e.getUTCMinutes()) + pad(e.getUTCSeconds()) + "Z";
    }
    // Rewrites UNTIL in the form the event needs (the all-day switch may have changed since it was written).
    function fixUntil(rule, allDay) {
        return String(rule).replace(/UNTIL=([^;]+)/, (all, v) => (/T/.test(v) === !allDay) ? all : "UNTIL=" + root.untilString(root.untilDay(v), allDay));
    }
    function parseRule(list, anchorMs) {
        const parts = {}, rule = root.ruleOf(list);
        if (rule) for (const piece of rule.slice(6).split(";")) { const i = piece.indexOf("="); if (i > 0) parts[piece.slice(0, i).toUpperCase()] = piece.slice(i + 1); }
        const anchor = new Date(anchorMs || Date.now());
        const st = {
            freq: ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].indexOf(parts.FREQ) !== -1 ? parts.FREQ : "WEEKLY",
            interval: Math.max(1, parseInt(parts.INTERVAL || "1") || 1),
            days: [], monthMode: "anchor", monthDays: [],
            nth: Math.ceil(anchor.getDate() / 7), nthDay: root.weekCodes[anchor.getDay()],
            months: [], raw: [], end: "never", until: 0, count: 10, extra: []
        };
        const known = { FREQ: 1, INTERVAL: 1, COUNT: 1, UNTIL: 1 };
        const byday = (parts.BYDAY || "").split(",").filter(x => x);
        const bymonthday = (parts.BYMONTHDAY || "").split(",").map(x => parseInt(x)).filter(x => !isNaN(x));
        const rawKeep = () => ["BYDAY", "BYMONTHDAY", "BYSETPOS"].filter(k => parts[k]).map(k => k + "=" + parts[k]);
        if (st.freq === "WEEKLY" && byday.length && byday.every(d => /^[A-Z]{2}$/.test(d))) { st.days = byday; known.BYDAY = 1; }
        else if (st.freq === "MONTHLY" || st.freq === "YEARLY") {
            if (parts.BYMONTH && st.freq === "YEARLY") { st.months = parts.BYMONTH.split(",").map(x => parseInt(x)).filter(x => x > 0 && x < 13); known.BYMONTH = 1; }
            if (byday.length === 1 && /^-?[1-5][A-Z]{2}$/.test(byday[0]) && !parts.BYMONTHDAY && !parts.BYSETPOS) {
                const m = byday[0].match(/^(-?\d)([A-Z]{2})$/); st.monthMode = "nth"; st.nth = +m[1]; st.nthDay = m[2]; known.BYDAY = 1;
            } else if (parts.BYDAY === "MO,TU,WE,TH,FR" && parts.BYSETPOS === "-1" && !parts.BYMONTHDAY) {
                st.monthMode = "lastWeekday"; known.BYDAY = 1; known.BYSETPOS = 1;
            } else if (bymonthday.length && !parts.BYDAY && !parts.BYSETPOS) {
                st.monthMode = "days"; st.monthDays = bymonthday; known.BYMONTHDAY = 1;
            } else if (parts.BYDAY || parts.BYMONTHDAY || parts.BYSETPOS) {
                st.monthMode = "raw"; st.raw = rawKeep(); known.BYDAY = known.BYMONTHDAY = known.BYSETPOS = 1;
            }
        }
        if (parts.COUNT) { st.end = "count"; st.count = Math.max(1, parseInt(parts.COUNT) || 1); }
        else if (parts.UNTIL) { st.end = "until"; st.until = root.untilDay(parts.UNTIL); }
        for (const k in parts) if (!known[k]) st.extra.push(k + "=" + parts[k]);
        if (!st.until) { const d = new Date(anchor.getFullYear(), anchor.getMonth() + 3, anchor.getDate()); st.until = d.getTime(); }
        return st;
    }
    function buildRule(st, allDay) {
        const out = ["FREQ=" + st.freq];
        if (st.interval > 1) out.push("INTERVAL=" + st.interval);
        if (st.freq === "WEEKLY" && st.days.length) out.push("BYDAY=" + root.weekOrder.filter(c => st.days.indexOf(c) !== -1).join(","));
        if (st.freq === "MONTHLY" || st.freq === "YEARLY") {
            if (st.monthMode === "days" && st.monthDays.length) out.push("BYMONTHDAY=" + st.monthDays.slice().sort((a, b) => (a < 0) - (b < 0) || a - b).join(","));
            else if (st.monthMode === "nth") out.push("BYDAY=" + st.nth + st.nthDay);
            else if (st.monthMode === "lastWeekday") out.push("BYDAY=MO,TU,WE,TH,FR", "BYSETPOS=-1");
            else if (st.monthMode === "raw") for (const x of st.raw) out.push(x);
            if (st.freq === "YEARLY" && st.months.length) out.push("BYMONTH=" + st.months.slice().sort((a, b) => a - b).join(","));
        }
        if (st.end === "count") out.push("COUNT=" + Math.max(1, st.count));
        else if (st.end === "until") out.push("UNTIL=" + root.untilString(st.until, allDay));
        for (const x of st.extra) out.push(x);
        return "RRULE:" + out.join(";");
    }
    // Same frequency card with fresh defaults: a pattern written for another frequency would mean nothing here.
    function retarget(st, freq, anchorMs) {
        const fresh = root.parseRule(["RRULE:FREQ=" + freq], anchorMs);
        return Object.assign({}, fresh, { interval: st.interval, end: st.end, until: st.until, count: st.count });
    }
    // Order of the parts does not matter: this is how presets recognise an equivalent written rule.
    function canonicalRule(rule) { return String(rule).slice(6).split(";").filter(x => x).sort().join(";"); }
    // END rule model
    function ordinalLabel(n) {
        if (n < 0) return root.tr("last", "dernier");
        return root.tr(["", "1st", "2nd", "3rd", "4th", "5th"][n] || n + "th", ["", "1er", "2e", "3e", "4e", "5e"][n] || n + "e");
    }
    function describeRule(list, anchorMs) {
        if (!root.ruleOf(list)) return "";
        const st = root.parseRule(list, anchorMs);
        const units = { DAILY: [root.tr("day", "jour"), root.tr("days", "jours")], WEEKLY: [root.tr("week", "semaine"), root.tr("weeks", "semaines")],
                        MONTHLY: [root.tr("month", "mois"), root.tr("months", "mois")], YEARLY: [root.tr("year", "an"), root.tr("years", "ans")] }[st.freq];
        let text = st.interval > 1 ? root.tr("Every %1 %2", "Tous les %1 %2").arg(st.interval).arg(units[1]) : root.tr("Every %1", "Chaque %1").arg(units[0]);
        const dayName = (code, fmt) => root.locale.dayName(root.weekCodes.indexOf(code), fmt);
        if (st.days.length) text += " · " + root.weekOrder.filter(c => st.days.indexOf(c) !== -1).map(c => dayName(c, Locale.ShortFormat)).join(", ");
        if (st.monthMode === "days") text += " · " + st.monthDays.slice().sort((a, b) => (a < 0) - (b < 0) || a - b).map(d => d < 0 ? root.tr("last day", "dernier jour") : root.tr("day %1", "le %1").arg(d)).join(", ");
        else if (st.monthMode === "nth") text += " · " + root.ordinalLabel(st.nth) + " " + dayName(st.nthDay, Locale.LongFormat);
        else if (st.monthMode === "lastWeekday") text += " · " + root.tr("last weekday", "dernier jour ouvré");
        if (st.freq === "YEARLY" && st.months.length) text += " · " + st.months.map(m => root.locale.standaloneMonthName(m - 1, Locale.ShortFormat)).join(", ");
        if (st.end === "count") text += " · " + root.tr("%1 times", "%1 fois").arg(st.count);
        else if (st.end === "until") text += " · " + root.tr("until %1", "jusqu'au %1").arg(new Date(st.until).toLocaleDateString(root.locale, "d MMM yyyy"));
        return text;
    }
    function presetOf(list) {
        const rule = root.ruleOf(list);
        if (!rule) return "none";
        const hit = root.repeatPresets.find(p => p.rule && root.canonicalRule(p.rule) === root.canonicalRule(rule));
        return hit ? hit.id : "custom";
    }
    function reminderLabel(m) {
        if (m === 0) return root.tr("At start", "Au début");
        if (m < 60) return m + " min";
        if (m < 1440) return (m / 60) + " h";
        if (m === 10080) return root.tr("1 week", "1 semaine");
        return (m / 1440) + root.tr(" day", " jour") + (m >= 2880 ? "s" : "");
    }
    // Plain text (or Google's light HTML) → StyledText with clickable links.
    function richText(text) {
        if (!text) return "";
        if (/<\w+[^>]*>/.test(text)) return text;
        const esc = String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return esc.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1">$1</a>').replace(/\n/g, "<br>");
    }

    function readableOn(c) {
        const col = Qt.color(c);
        const linear = c => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        const luminance = 0.2126 * linear(col.r) + 0.7152 * linear(col.g) + 0.0722 * linear(col.b);
        return luminance > 0.179 ? "#000000" : "#ffffff";
    }

    // Nerd Font glyphs (Material Design range) used across the calendar UI.
    readonly property var icon: ({
        calendar: String.fromCodePoint(0xF00ED), today: String.fromCodePoint(0xF00F6), plus: String.fromCodePoint(0xF0415),
        search: String.fromCodePoint(0xF0349), sync: String.fromCodePoint(0xF04E6), cog: String.fromCodePoint(0xF0493),
        close: String.fromCodePoint(0xF0156), left: String.fromCodePoint(0xF0141), right: String.fromCodePoint(0xF0142),
        place: String.fromCodePoint(0xF034E), video: String.fromCodePoint(0xF0567), clock: String.fromCodePoint(0xF0150),
        bell: String.fromCodePoint(0xF009A), repeat: String.fromCodePoint(0xF0456), trash: String.fromCodePoint(0xF01B4),
        edit: String.fromCodePoint(0xF03EB), check: String.fromCodePoint(0xF012C), google: String.fromCodePoint(0xF02AD),
        link: String.fromCodePoint(0xF0337), offline: String.fromCodePoint(0xF0164), back: String.fromCodePoint(0xF004D),
        eye: String.fromCodePoint(0xF0208), eyeOff: String.fromCodePoint(0xF0209), notes: String.fromCodePoint(0xF0219),
        people: String.fromCodePoint(0xF0849), help: String.fromCodePoint(0xF02D7), palette: String.fromCodePoint(0xF03D8),
        expand: String.fromCodePoint(0xF0293), copy: String.fromCodePoint(0xF018F), open: String.fromCodePoint(0xF03CC),
        alert: String.fromCodePoint(0xF0026), rss: String.fromCodePoint(0xF046B), account: String.fromCodePoint(0xF0004),
        sun: String.fromCodePoint(0xF0599), list: String.fromCodePoint(0xF0279), month: String.fromCodePoint(0xF0B0A),
        week: String.fromCodePoint(0xF1A41), day: String.fromCodePoint(0xF00F6), cloud: String.fromCodePoint(0xF015F)
    })

    // ------------------------------------------------------------------ actions

    signal actionFinished(string command, var result)

    function openAgenda(view, date, eventId) {
        if (!root.enabled) return;
        if (view) root.agendaView = view;
        if (date) root.focusDate = root.startOfDay(date);
        root.openEventId = eventId || "";
        root.agendaOpen = true;
        if (!DashboardController.isVisible) DashboardController.show();
        root.syncIfStale();
    }
    function closeAgenda() { root.agendaOpen = false; }
    // Accounts and preferences live in Settings → Calendar.
    function openSettings() {
        DashboardController.hide();
        Quickshell.execDetached(["serpantinum", "settings", "addon_calendar"]);
    }
    property var escapeHandler: null
    function handleEscape() { return root.agendaOpen && root.escapeHandler ? root.escapeHandler() : false; }
    function ago(epochSeconds) {
        const m = Math.max(0, Math.round((root.now / 1000 - epochSeconds) / 60));
        if (m < 1) return root.tr("just now", "à l'instant");
        if (m < 60) return root.tr("%1 min ago", "il y a %1 min").arg(m);
        return root.tr("%1 h ago", "il y a %1 h").arg(Math.round(m / 60));
    }
    function selectDay(d) { root.selectedDay = d && !root.sameDay(d, root.today) ? root.startOfDay(d) : null; }

    function sync() { if (root.enabled && (root.available || root.google)) root.run(["sync"]); }
    function syncIfStale() {
        const lastSync = root.state ? root.state.lastSync || 0 : 0;
        const age = Date.now() - lastSync * 1000;
        if (!root.syncing && (age < 0 || age >= 5 * 60000)) root.sync();
    }
    function ensure(from, to) {
        if (!root.available) return;
        if (from >= root.range.from && to <= root.range.to) return;
        root.run(["ensure", String(Math.floor(from)), String(Math.ceil(to))]);
    }
    function connect(clientId, clientSecret) {
        if (root.connectProc) return;
        root.connectError = "";
        root.browserOpenFailed = false;
        root.run(["connect", "--client-id", clientId, "--client-secret", clientSecret, "--no-browser"], null, true);
    }
    function openAuthBrowser() {
        if (root.authUrl) root.browserOpenFailed = !Qt.openUrlExternally(root.authUrl);
    }

    function connectionError(result) {
        switch (result.reason) {
        case "client_id": return tr(result.error, "L’ID client doit se terminer par .apps.googleusercontent.com.");
        case "client_secret": return tr(result.error, "Saisis le secret du client OAuth.");
        case "callback_unavailable": return tr(result.error, "Impossible de démarrer le serveur local qui reçoit la réponse de Google.");
        case "timeout": return tr(result.error, "Google n’a pas répondu dans les 5 minutes. Relance la connexion et termine-la dans ton navigateur.");
        case "access_denied": return tr(result.error, "Google a refusé l’accès. Autorise l’accès à Agenda dans ton navigateur, puis réessaie.");
        case "callback_mismatch": return tr(result.error, "La réponse ne correspond pas à cette tentative. Relance la connexion et utilise le dernier onglet ouvert.");
        case "network": return tr(result.error, "Impossible de joindre Google pour terminer la connexion. Vérifie ta connexion Internet, puis réessaie.");
        case "invalid_client": return tr(result.error, "Google a rejeté le client OAuth. Vérifie que l’ID et le secret viennent du même client « Application de bureau ».");
        case "invalid_grant": return tr(result.error, "Google a rejeté le code d’autorisation. Relance la connexion et termine-la dans le dernier onglet ouvert.");
        case "no_refresh_token": return tr(result.error, "Google n’a pas accordé l’accès permanent. Retire l’accès de cette application dans ton compte Google, puis réessaie.");
        case "sync_offline": return tr(result.error, "Google est connecté. Vérifie ta connexion Internet pour terminer la synchronisation de tes agendas.");
        default: return result.error;
        }
    }
    function cancelConnect() {
        if (!root.connectProc || root.connectProc.cancelRequested) return;
        root.connectProc.cancelRequested = true;
        root.connectProc.signal(15);
    }
    function disconnect() { root.connectError = ""; root.run(["disconnect"]); }
    function create(payload, cb) { root.run(["create", JSON.stringify(payload)], cb); }
    function update(payload, cb) { root.run(["update", JSON.stringify(payload)], cb); }
    function remove(payload, cb) { root.run(["delete", JSON.stringify(payload)], cb); }
    function rsvp(e, response) { root.run(["rsvp", JSON.stringify({ id: e.id, calendarId: e.calendarId, response: response })]); }
    function setPrefs(payload) { root.run(["prefs", JSON.stringify(payload)]); }
    function toggleCalendar(id) {
        const hidden = (root.prefs.hidden || []).slice();
        const at = hidden.indexOf(id);
        if (at === -1) hidden.push(id); else hidden.splice(at, 1);
        // Local echo so the toggle animates instantly; the backend republishes the same value.
        if (root.state) {
            const copy = Object.assign({}, root.state);
            copy.prefs = Object.assign({}, copy.prefs, { hidden: hidden });
            copy.calendars = copy.calendars.map(c => Object.assign({}, c, { visible: hidden.indexOf(c.id) === -1 }));
            root.state = copy;
        }
        root.setPrefs({ hidden: hidden });
    }
    function addIcs(url, name, cb) { root.run(["ics-add", JSON.stringify({ url: url, name: name || "" })], cb); }
    function removeIcs(id) { root.run(["ics-remove", id]); }

    property var connectProc: null
    property Component processComponent: Component {
        Process {
            id: proc
            property var callback: null
            property string verb: ""
            property bool cancelRequested: false
            stdout: StdioCollector { id: out }
            onExited: (code) => {
                let result = null;
                try { result = JSON.parse(out.text.trim().split("\n").pop() || "{}"); } catch (e) { result = { ok: code === 0 }; }
                if (root.connectProc === proc) {
                    if (proc.cancelRequested && !(result && result.ok === true)) {
                        result = { cancelled: true };
                    } else if (result && result.ok === false && result.error) {
                        root.connectError = root.connectionError(result);
                    } else if (code !== 0) {
                        root.connectError = root.tr("The calendar helper stopped unexpectedly (exit code %1).", "Le service Agenda s’est arrêté pendant la connexion (code %1).").arg(code);
                    }
                    root.connectProc = null;
                } else {
                    if (result && result.ok === false && result.error) root.lastError = result.error;
                    else if (code === 0) root.lastError = "";
                    if (proc.verb === "sync" && result && result.ok === true && root.google) root.connectError = "";
                    root.busy = Math.max(0, root.busy - 1);
                }
                if (proc.callback) proc.callback(result || {});
                root.actionFinished(proc.verb, result || {});
                root.file.reload();
                proc.destroy();
            }
        }
    }
    function run(args, cb, isConnect) {
        const proc = root.processComponent.createObject(root, { command: ["python3", root.backend].concat(args), callback: cb || null, verb: args[0] });
        if (!proc) {
            if (isConnect) root.connectError = root.tr("Could not start the calendar helper.", "Impossible de démarrer le service local de l’agenda.");
            return;
        }
        if (isConnect) root.connectProc = proc;
        else root.busy++;
        proc.running = true;
    }

    property FileView file: FileView {
        path: Caching.stateDir + "/gcal/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.state = JSON.parse(text()); } catch (e) { /* half-written: keep the last good state */ }
        }
    }

    property Timer clock: Timer {
        interval: 15000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
}
