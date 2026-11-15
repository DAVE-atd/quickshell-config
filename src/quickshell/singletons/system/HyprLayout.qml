pragma Singleton
// Hyprland tiling layout switcher (idea: WilliamAWSOFTWARE/dms-hypr-workspace-manager, MIT; own code).
// Sets general:layout / master:orientation at runtime via `hyprctl eval`: global, and only until
// the next Hyprland config reload. Used by the bar module "layout" and layout/LayoutPopup.qml.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root

    // rects: wireframe for layout/LayoutPreview.qml as [x, y, w, h] fractions, first = main window
    readonly property var layouts: [
        { id: "dwindle",   name: "Dwindle",  layout: "dwindle",   orientation: "",
          rects: [[0, 0, .5, 1], [.5, 0, .5, .5], [.5, .5, .25, .5], [.75, .5, .25, .5]] },
        { id: "left",      name: "Tile",     layout: "master",    orientation: "left",
          rects: [[0, 0, .6, 1], [.6, 0, .4, .5], [.6, .5, .4, .5]] },
        { id: "right",     name: "Right",    layout: "master",    orientation: "right",
          rects: [[.4, 0, .6, 1], [0, 0, .4, .5], [0, .5, .4, .5]] },
        { id: "top",       name: "Top",      layout: "master",    orientation: "top",
          rects: [[0, 0, 1, .6], [0, .6, .5, .4], [.5, .6, .5, .4]] },
        { id: "bottom",    name: "Bottom",   layout: "master",    orientation: "bottom",
          rects: [[0, .4, 1, .6], [0, 0, .5, .4], [.5, 0, .5, .4]] },
        { id: "center",    name: "Center",   layout: "master",    orientation: "center",
          rects: [[.25, 0, .5, 1], [0, 0, .25, 1], [.75, 0, .25, 1]] },
        { id: "scrolling", name: "Scroll",   layout: "scrolling", orientation: "",
          rects: [[0, 0, .45, 1], [.45, 0, .45, 1], [.9, 0, .1, 1]] },
        { id: "monocle",   name: "Monocle",  layout: "monocle",   orientation: "",
          rects: [[0, 0, 1, 1]] }
    ]

    property string current: "dwindle"
    property string previous: "dwindle"
    readonly property var currentEntry: byId(current) || layouts[0]

    function byId(id) {
        for (let i = 0; i < layouts.length; i++) if (layouts[i].id === id) return layouts[i];
        return null;
    }

    function set(id) {
        let l = byId(id);
        if (!l || id === current) return;
        previous = current;
        current = id;
        apply();
    }

    // One hyprctl at a time: detached calls from fast scrolling could finish out of order
    property string applied: ""
    function apply() {
        if (applyProc.running) return;
        let l = currentEntry;
        applied = current;
        applyProc.command = ["hyprctl", "eval", "hl.config({ general = { layout = '" + l.layout + "' }"
            + (l.orientation ? ", master = { orientation = '" + l.orientation + "' }" : "") + " })"];
        applyProc.running = true;
    }
    Process {
        id: applyProc
        onExited: if (root.applied !== root.current) root.apply()
    }

    function cycle(dir) {
        let i = layouts.indexOf(currentEntry);
        set(layouts[(i + dir + layouts.length) % layouts.length].id);
    }

    // Right click on the pill: monocle and back
    function toggle(id) { set(current === id ? previous : id); }

    function refresh() { queryProc.running = true; }

    Process {
        id: queryProc
        command: ["hyprctl", "--batch", "j/getoption general:layout ; j/getoption master:orientation"]
        stdout: StdioCollector {
            onStreamFinished: {
                let m = this.text.match(/"str":\s*"[^"]*"/g);
                if (!m || m.length < 2) return;
                let layout = m[0].replace(/.*"([^"]*)"$/, "$1"), orientation = m[1].replace(/.*"([^"]*)"$/, "$1");
                for (let i = 0; i < root.layouts.length; i++) {
                    let l = root.layouts[i];
                    if (l.layout === layout && (!l.orientation || l.orientation === orientation)) {
                        root.current = l.id;
                        return;
                    }
                }
            }
        }
    }

    // A config reload drops the runtime value
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") root.refresh(); }
    }

    Component.onCompleted: refresh()
}
