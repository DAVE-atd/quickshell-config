pragma Singleton
import QtQuick

// Stand-in: Serpantinum locks with hyprlock (a separate process), so the
// shell itself never sees a locked session.
QtObject { property bool locked: false }
