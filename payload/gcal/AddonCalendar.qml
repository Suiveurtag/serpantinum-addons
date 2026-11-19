import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Direct ShellRoot child: IPC entry points (Super+G, Super+I, reminder notifications) for the calendar addon.
Scope {
    IpcHandler {
        target: "addonCalendar"
        function toggle(): void {
            if (DashboardController.isVisible && GCal.agendaOpen) DashboardController.hide();
            else GCal.openAgenda();
        }
        function open(): void { GCal.openAgenda(); }
        function openEvent(id: string): void {
            const e = GCal.find(id);
            GCal.openAgenda("day", e ? new Date(e.start) : null, id);
        }
        function newEvent(): void { GCal.openEventId = "new"; GCal.openAgenda(); }
        function sync(): void { GCal.sync(); }
    }
}
