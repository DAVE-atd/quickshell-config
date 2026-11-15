import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../../"
import "../../../reusables"
import "../../../reusables/guide"

BarModuleCard {
    id: card
    title: I18n.t("guide.bar.modules.sysmon", "System monitor")
    moduleId: "sysmon"
    previewSideHeight: 150

    widgetComponent: Component {
        BarPreviewWidget {
            property string sysmonStyle: tab.sysmonStyle
            property var sysmonStats: tab.sysmonStats
            property bool sysmonShowText: tab.sysmonShowText
        }
    }

    SettingsRow {
        rootObj: card.rootObj
        settingId: "bar_sysmon_style"
        searchKeywords: "sysmon system monitor style gauge ring bar icon"
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󱐋"
        title: I18n.t("guide.bar.sysmon.look.title", "Style")
        description: I18n.t("guide.bar.sysmon.look.desc", "Gauge ring, progress bar or icon only")

        Switch {
            id: lookSwitch
            readonly property var ids: ["gauge", "bar", "plain"]
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            implicitWidth: rootObj.s(240)
            implicitHeight: rootObj.s(32)
            cornerRadius: ThemeBackend.borderRadius
            fontPixelSize: rootObj.s(11)
            options: [
                I18n.t("guide.bar.sysmon.look.gauge", "Gauge"),
                I18n.t("guide.bar.sysmon.look.bar", "Bar"),
                I18n.t("guide.bar.sysmon.look.plain", "Icon")
            ]
            currentIndex: Math.max(0, ids.indexOf(card.tab.sysmonStyle))
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface0
            textColor: ThemeBackend.text
            activeTextColor: ThemeBackend.crust
            onValueChanged: function(index, value) {
                card.tab.setSysmonStyle(lookSwitch.ids[index]);
            }
        }
    }

    SettingsRow {
        rootObj: card.rootObj
        settingId: "bar_sysmon_text"
        searchKeywords: "sysmon value text percent number"
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰉿"
        title: I18n.t("guide.bar.sysmon.text.title", "Show values")
        description: I18n.t("guide.bar.sysmon.text.desc", "Display the number next to each icon")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: card.tab.sysmonShowText
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                card.tab.setSysmonShowText(c);
            }
        }
    }

    SettingsRow {
        rootObj: card.rootObj
        settingId: "bar_sysmon_cpu"
        searchKeywords: "sysmon cpu processor load usage"
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰍛"
        title: I18n.t("guide.bar.sysmon.cpu.title", "CPU usage")
        description: I18n.t("guide.bar.sysmon.cpu.desc", "Display processor utilization ring")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: card.tab.isSysmonStatEnabled("cpu")
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                card.tab.toggleSysmonStat("cpu", c);
            }
        }
    }

    SettingsRow {
        rootObj: card.rootObj
        settingId: "bar_sysmon_ram"
        searchKeywords: "sysmon ram memory usage"
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰘚"
        title: I18n.t("guide.bar.sysmon.ram.title", "Memory usage")
        description: I18n.t("guide.bar.sysmon.ram.desc", "Display memory (RAM) utilization ring")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: card.tab.isSysmonStatEnabled("ram")
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                card.tab.toggleSysmonStat("ram", c);
            }
        }
    }

    SettingsRow {
        rootObj: card.rootObj
        settingId: "bar_sysmon_temp"
        searchKeywords: "sysmon temperature temp degrees"
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰔏"
        title: I18n.t("guide.bar.sysmon.temp.title", "Temperature")
        description: I18n.t("guide.bar.sysmon.temp.desc", "Display system temperature ring")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: card.tab.isSysmonStatEnabled("temp")
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                card.tab.toggleSysmonStat("temp", c);
            }
        }
    }

    SettingsRow {
        rootObj: card.rootObj
        settingId: "bar_sysmon_disk"
        searchKeywords: "sysmon disk storage usage space drive"
        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
        icon: "󰋊"
        title: I18n.t("guide.bar.sysmon.disk.title", "Disk usage")
        description: I18n.t("guide.bar.sysmon.disk.desc", "Display storage disk utilization ring")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: card.tab.isSysmonStatEnabled("disk")
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                card.tab.toggleSysmonStat("disk", c);
            }
        }
    }
}
