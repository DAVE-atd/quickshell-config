pragma Singleton
import QtQuick
import Quickshell

// DMS toasts as desktop notifications (Serpantinum shows them)
QtObject {
    function _send(urgency, msg, details) {
        Quickshell.execDetached(["notify-send", "--app-name=Serpantinum", "--urgency=" + urgency, msg, details || ""])
    }
    function showInfo(msg, details) { _send("low", msg, details) }
    function showWarning(msg, details) { _send("normal", msg, details) }
    function showError(msg, details) { _send("critical", msg, details) }
}
