/*
 * Claude Usage — plasmoide para o painel do Plasma 6.
 *
 * Mostra os limites de uso do Claude Code (janela de 5h e semanal) lidos da
 * API OAuth da Anthropic, via o script contents/scripts/fetch-usage.sh.
 *
 * Representação compacta: anel duplo (5h externo, 7d interno) com o maior
 * percentual no centro. Representação completa (popup): barras detalhadas,
 * countdown até o reset e créditos extras.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---- estado ----
    property bool   ok: false
    property string errText: "carregando..."
    property real   fiveHourPct: 0
    property real   sevenDayPct: 0
    property string fiveHourReset: ""
    property string sevenDayReset: ""
    property bool   extraEnabled: false
    property real   extraUsed: 0
    property string extraCurrency: ""
    property double now: 0

    readonly property real primaryPct: Math.max(fiveHourPct, sevenDayPct)
    readonly property string scriptPath:
        Qt.resolvedUrl("../scripts/fetch-usage.sh").toString().replace(/^file:\/\//, "")

    // Verde -> amarelo -> vermelho conforme o uso sobe.
    function severityColor(p) {
        if (p >= 90) return Kirigami.Theme.negativeTextColor
        if (p >= 70) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }

    // "6d 3h" / "2h 13m" / "44m" / "resetando..." a partir de um ISO timestamp.
    function remaining(iso) {
        if (!iso) return ""
        var t = Date.parse(iso)
        if (isNaN(t)) return ""
        var d = t - root.now
        if (d <= 0) return "resetando..."
        var days = Math.floor(d / 86400000)
        var h = Math.floor((d % 86400000) / 3600000)
        var m = Math.floor((d % 3600000) / 60000)
        if (days > 0) return days + "d " + h + "h"
        if (h > 0)    return h + "h " + m + "m"
        return m + "m"
    }

    Plasmoid.icon: "utilities-system-monitor"
    toolTipMainText: "Claude Usage"
    toolTipSubText: ok
        ? ("5h: " + fiveHourPct.toFixed(0) + "%   •   7d: " + sevenDayPct.toFixed(0) + "%")
        : ("Erro: " + errText)

    // ---- coleta de dados ----
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            exec.disconnectSource(source)
            var out = ((data && data["stdout"]) || "").trim()
            try {
                var j = JSON.parse(out)
                if (j.ok) {
                    root.ok = true
                    root.errText = ""
                    root.fiveHourPct   = j.five_hour.pct
                    root.sevenDayPct   = j.seven_day.pct
                    root.fiveHourReset = j.five_hour.resets_at
                    root.sevenDayReset = j.seven_day.resets_at
                    root.extraEnabled  = j.extra.enabled
                    root.extraUsed     = j.extra.used
                    root.extraCurrency = j.extra.currency
                } else {
                    root.ok = false
                    root.errText = j.error || "desconhecido"
                }
            } catch (e) {
                root.ok = false
                root.errText = "parse: " + out.substring(0, 80)
            }
        }
    }

    function refresh() {
        exec.connectSource("bash " + JSON.stringify(root.scriptPath))
    }

    Component.onCompleted: { root.now = Date.now(); refresh() }

    Timer {  // poll da API
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {  // relógio para o countdown; só corre com o popup aberto
        interval: 1000
        running: root.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    // ============================================================
    //  Representação compacta (no painel): anel duplo
    // ============================================================
    compactRepresentation: MouseArea {
        id: compactRoot
        readonly property bool horizontal:
            Plasmoid.formFactor === PlasmaCore.Types.Horizontal

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: horizontal ? height : Kirigami.Units.gridUnit * 2
        Layout.preferredHeight: horizontal ? Kirigami.Units.gridUnit * 2 : width

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton) root.refresh()
            else root.expanded = !root.expanded
        }

        Canvas {
            id: ring
            anchors.fill: parent
            anchors.margins: Math.round(Math.min(width, height) * 0.06)

            function faint(c) { return Qt.rgba(c.r, c.g, c.b, 0.18) }

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2, cy = height / 2
                var outer = Math.min(width, height) / 2 - 1
                var lw = Math.max(2, outer * 0.20)
                var bg = faint(Kirigami.Theme.textColor)

                function arc(radius, pct, col) {
                    var start = -Math.PI / 2
                    ctx.lineWidth = lw
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.strokeStyle = bg
                    ctx.arc(cx, cy, radius, 0, 2 * Math.PI)
                    ctx.stroke()
                    if (pct > 0) {
                        ctx.beginPath()
                        ctx.strokeStyle = col
                        ctx.arc(cx, cy, radius, start,
                                start + 2 * Math.PI * Math.min(pct, 100) / 100)
                        ctx.stroke()
                    }
                }

                arc(outer, root.fiveHourPct, root.severityColor(root.fiveHourPct))
                arc(outer - lw - 1.5, root.sevenDayPct, root.severityColor(root.sevenDayPct))
            }

            Connections {
                target: root
                function onFiveHourPctChanged() { ring.requestPaint() }
                function onSevenDayPctChanged() { ring.requestPaint() }
            }
            Connections {
                target: Kirigami.Theme
                function onTextColorChanged() { ring.requestPaint() }
            }

            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: root.ok ? root.primaryPct.toFixed(0) : "!"
                color: root.ok ? root.severityColor(root.primaryPct)
                                : Kirigami.Theme.negativeTextColor
                font.pixelSize: Math.max(8, Math.round(parent.height * 0.32))
                font.bold: true
            }
        }
    }

    // ============================================================
    //  Representação completa (popup)
    // ============================================================
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 13

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    text: "Uso do Claude"
                    level: 3
                    Layout.fillWidth: true
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    text: "Atualizar"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    onClicked: root.refresh()
                    PlasmaComponents.ToolTip.text: "Atualizar agora"
                }
            }

            // ---- estado de erro ----
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: !root.ok
                type: Kirigami.MessageType.Warning
                text: root.errText
            }

            // ---- barra reutilizável ----
            component UsageBar: ColumnLayout {
                property string label
                property real pct
                property string reset
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: label; Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: pct.toFixed(0) + "%"
                        color: root.severityColor(pct)
                        font.bold: true
                    }
                }
                PlasmaComponents.ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: 100; value: pct
                }
                PlasmaComponents.Label {
                    visible: reset !== ""
                    text: "reseta em " + root.remaining(reset)
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }

            UsageBar {
                visible: root.ok
                label: "Sessão (5h)"
                pct: root.fiveHourPct
                reset: root.fiveHourReset
            }
            UsageBar {
                visible: root.ok
                label: "Semanal (7 dias)"
                pct: root.sevenDayPct
                reset: root.sevenDayReset
            }

            Kirigami.Separator { Layout.fillWidth: true; visible: root.ok }

            RowLayout {
                Layout.fillWidth: true
                visible: root.ok
                PlasmaComponents.Label { text: "Créditos extras"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.extraEnabled
                        ? (root.extraUsed.toFixed(2) + " " + root.extraCurrency)
                        : "desativado"
                    opacity: root.extraEnabled ? 1.0 : 0.6
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
