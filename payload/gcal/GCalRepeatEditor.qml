import QtQuick
import QtQuick.Layouts
import "../"

// Advanced repeat editor: interval and unit, weekdays, monthly / yearly patterns (day of the month, "3rd Tuesday",
// last weekday, chosen months), and how the series ends. Works on the event's recurrence list: every edit rebuilds
// the RRULE line from GCal.parseRule / buildRule and hands the new list back through `edited`.
Item {
    id: root
    property var rule: []                     // recurrence list of the event (RRULE / EXDATE lines)
    property double anchor: 0                 // start of the event: defaults and the first occurrence
    property bool allDay: false
    property color accent: ThemeBackend.mauve
    signal edited(var list)
    function s(v) { return Scaler.s(v); }

    readonly property var st: GCal.parseRule(rule, anchor)
    readonly property var anchorDate: new Date(anchor)
    readonly property string anchorCode: GCal.weekCodes[anchorDate.getDay()]
    // Narrow views of `st`: a change notifies only when the value itself changes, so segmented controls keep their delegates.
    readonly property string freq: st.freq
    readonly property int interval: st.interval
    readonly property string endMode: st.end
    readonly property bool monthly: freq === "MONTHLY" || freq === "YEARLY"
    readonly property var dayOrder: GCal.prefs.weekStart === 0 ? ["SU"].concat(GCal.weekOrder.slice(0, 6)) : GCal.weekOrder
    readonly property var effectiveDays: st.days.length ? st.days : [anchorCode]
    readonly property var effectiveMonths: st.months.length ? st.months : [anchorDate.getMonth() + 1]
    property bool untilPicker: false
    implicitHeight: col.implicitHeight

    function patch(obj) { root.edited(GCal.withRule(root.rule, GCal.buildRule(Object.assign({}, root.st, obj), root.allDay))); }
    function dayLabel(code) { return GCal.locale.dayName(GCal.weekCodes.indexOf(code), Locale.ShortFormat).replace(".", "").slice(0, 3); }
    function toggled(list, value) {
        const at = list.indexOf(value);
        return at === -1 ? list.concat([value]) : list.filter(x => x !== value);
    }
    function setMode(mode) {
        patch({ monthMode: mode, raw: [], monthDays: mode === "days" ? [anchorDate.getDate()] : [] });
    }
    function setEnd(mode) {
        root.untilPicker = false;
        patch({ end: mode });
    }
    function unit(freq, n) {
        return { DAILY: n > 1 ? GCal.tr("days", "jours") : GCal.tr("day", "jour"), WEEKLY: n > 1 ? GCal.tr("weeks", "semaines") : GCal.tr("week", "semaine"),
                 MONTHLY: n > 1 ? GCal.tr("months", "mois") : GCal.tr("month", "mois"), YEARLY: n > 1 ? GCal.tr("years", "ans") : GCal.tr("year", "an") }[freq];
    }
    component Caption: Text {
        font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: Scaler.s(11.5)
        color: ThemeBackend.overlay1
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: root.s(10)

        // Every N units.
        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(8)
            Caption { text: GCal.tr("Every", "Tous les") }
            GCalStepper {
                accent: root.accent
                value: root.interval
                onMoved: (v) => root.patch({ interval: v })
            }
            GCalSegmented {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(34)
                accent: root.accent
                fontSize: root.s(11)
                current: root.freq
                options: ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].map(f => ({ id: f, label: root.unit(f, root.interval) }))
                onSelected: (id) => { if (id !== root.freq) root.edited(GCal.withRule(root.rule, GCal.buildRule(GCal.retarget(root.st, id, root.anchor), root.allDay))); }
            }
        }

        // Weekdays.
        GCalCollapse {
            open: root.freq === "WEEKLY"
            ColumnLayout {
                width: parent.width
                spacing: root.s(6)
                Caption { text: GCal.tr("On", "Les") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(5)
                    Repeater {
                        model: root.dayOrder
                        GCalRepeatCell {
                            required property string modelData
                            text: root.dayLabel(modelData)
                            accent: root.accent
                            on: root.effectiveDays.indexOf(modelData) !== -1
                            onClicked: {
                                const next = root.toggled(root.effectiveDays, modelData);
                                if (next.length) root.patch({ days: next });
                            }
                        }
                    }
                }
            }
        }

        // Monthly / yearly pattern.
        GCalCollapse {
            open: root.monthly
            ColumnLayout {
                width: parent.width
                spacing: root.s(8)
                Caption { text: GCal.tr("Months", "Mois"); visible: root.freq === "YEARLY" }
                GridLayout {
                    visible: root.freq === "YEARLY"
                    Layout.fillWidth: true
                    columns: 6
                    rowSpacing: root.s(5); columnSpacing: root.s(5)
                    Repeater {
                        model: 12
                        GCalRepeatCell {
                            required property int index
                            text: GCal.locale.standaloneMonthName(index, Locale.ShortFormat).replace(".", "").slice(0, 4)
                            accent: root.accent
                            on: root.effectiveMonths.indexOf(index + 1) !== -1
                            onClicked: {
                                const next = root.toggled(root.effectiveMonths, index + 1);
                                if (next.length) root.patch({ months: next });
                            }
                        }
                    }
                }
                Caption { text: GCal.tr("Pattern", "Motif") }
                Flow {
                    Layout.fillWidth: true
                    spacing: root.s(6)
                    GCalChip {
                        text: root.freq === "YEARLY" ? GCal.tr("Same day", "Même jour") : GCal.tr("On day %1", "Le %1").arg(root.anchorDate.getDate())
                        accent: root.accent
                        selected: root.st.monthMode === "anchor"
                        onClicked: root.setMode("anchor")
                    }
                    GCalChip {
                        text: GCal.tr("Specific days", "Jours précis")
                        accent: root.accent
                        selected: root.st.monthMode === "days"
                        onClicked: root.setMode("days")
                    }
                    GCalChip {
                        text: GCal.tr("Nth weekday (4th Friday…)", "Nᵉ jour de semaine (4ᵉ vendredi…)")
                        accent: root.accent
                        selected: root.st.monthMode === "nth"
                        onClicked: root.setMode("nth")
                    }
                    GCalChip {
                        text: GCal.tr("Last weekday", "Dernier jour ouvré")
                        accent: root.accent
                        selected: root.st.monthMode === "lastWeekday"
                        onClicked: root.setMode("lastWeekday")
                    }
                    GCalChip {
                        visible: root.st.monthMode === "raw"
                        text: GCal.tr("Current pattern", "Motif actuel")
                        accent: root.accent
                        selected: true
                    }
                }
                // Days of the month.
                GCalCollapse {
                    open: root.st.monthMode === "days"
                    GridLayout {
                        width: parent.width
                        columns: 8
                        rowSpacing: root.s(5); columnSpacing: root.s(5)
                        Repeater {
                            model: 31
                            GCalRepeatCell {
                                required property int index
                                text: String(index + 1)
                                accent: root.accent
                                on: root.st.monthDays.indexOf(index + 1) !== -1
                                onClicked: {
                                    const next = root.toggled(root.st.monthDays, index + 1);
                                    if (next.length) root.patch({ monthDays: next });
                                }
                            }
                        }
                        GCalRepeatCell {
                            text: GCal.tr("last", "dern.")
                            fontSize: root.s(9.5)
                            accent: root.accent
                            on: root.st.monthDays.indexOf(-1) !== -1
                            onClicked: {
                                const next = root.toggled(root.st.monthDays, -1);
                                if (next.length) root.patch({ monthDays: next });
                            }
                        }
                    }
                }
                // Nth weekday.
                GCalCollapse {
                    open: root.st.monthMode === "nth"
                    ColumnLayout {
                        width: parent.width
                        spacing: root.s(6)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(5)
                            Repeater {
                                model: [1, 2, 3, 4, 5, -1]
                                GCalRepeatCell {
                                    required property int modelData
                                    text: GCal.ordinalLabel(modelData)
                                    accent: root.accent
                                    on: root.st.nth === modelData
                                    onClicked: root.patch({ nth: modelData })
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(5)
                            Repeater {
                                model: root.dayOrder
                                GCalRepeatCell {
                                    required property string modelData
                                    text: root.dayLabel(modelData)
                                    accent: root.accent
                                    on: root.st.nthDay === modelData
                                    onClicked: root.patch({ nthDay: modelData })
                                }
                            }
                        }
                    }
                }
            }
        }

        // End.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.s(8)
            Caption { text: GCal.tr("Ends", "Fin") }
            GCalSegmented {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(34)
                accent: root.accent
                fontSize: root.s(11)
                current: root.endMode
                options: [{ id: "never", label: GCal.tr("Never", "Jamais") }, { id: "until", label: GCal.tr("On a date", "À une date") },
                          { id: "count", label: GCal.tr("After", "Après") }]
                onSelected: (id) => root.setEnd(id)
            }
            GCalCollapse {
                open: root.endMode === "until"
                ColumnLayout {
                    width: parent.width
                    spacing: 0
                    GCalFieldButton {
                        Layout.fillWidth: true
                        text: new Date(root.st.until).toLocaleDateString(GCal.locale, "ddd d MMMM yyyy")
                        active: root.untilPicker
                        accent: root.accent
                        onClicked: root.untilPicker = !root.untilPicker
                        onWheelStep: (dir) => root.patch({ until: Math.max(GCal.startOfDay(root.anchor).getTime(), GCal.addDays(root.st.until, dir * 7).getTime()) })
                    }
                    GCalCollapse {
                        open: root.untilPicker
                        GCalMiniMonth {
                            y: root.s(8)
                            width: Math.min(parent.width, root.s(280))
                            selected: GCal.startOfDay(root.st.until)
                            accent: root.accent
                            showDots: false
                            onPicked: (d) => {
                                root.untilPicker = false;
                                root.patch({ until: Math.max(GCal.startOfDay(root.anchor).getTime(), GCal.startOfDay(d).getTime()) });
                            }
                        }
                    }
                }
            }
            GCalCollapse {
                open: root.endMode === "count"
                RowLayout {
                    width: parent.width
                    spacing: root.s(8)
                    GCalStepper {
                        accent: root.accent
                        to: 999
                        value: root.st.count
                        onMoved: (v) => root.patch({ count: v })
                    }
                    Caption { text: GCal.tr("occurrences", "occurrences") }
                }
            }
        }

        // Summary.
        Text {
            Layout.fillWidth: true
            text: GCal.describeRule(root.rule, root.anchor)
            wrapMode: Text.WordWrap
            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(11.5)
            color: root.accent
        }
    }
}
