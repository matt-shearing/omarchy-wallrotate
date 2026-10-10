import QtQuick
import qs.Commons
import qs.Ui

// Bar chip for the rotator. It holds no timer of its own; the service does
// the work, so adding the chip to several monitors costs nothing extra.
BarWidget {
  id: root

  readonly property var rotator: bar && bar.shell ? bar.shell.serviceFor("contra.wallrotate") : null
  readonly property bool paused: rotator ? rotator.paused : false
  readonly property color contentFg: bar ? bar.foreground : Color.foreground

  readonly property string glyphImages: String.fromCodePoint(0xF1A00)
  readonly property string glyphPaused: String.fromCodePoint(0xF0E09)

  // Recomputed on hover so the countdown is fresh without a ticking timer.
  property string tooltip: ""

  function refreshTooltip() {
    if (rotator) rotator.reloadConfig()
    if (!rotator) {
      tooltip = "Wallpaper rotation unavailable"
      return
    }
    var head = paused
      ? "Wallpaper rotation paused"
      : "Next wallpaper in " + rotator.minutesLeft() + " min"
    var mode = rotator.shuffle ? "shuffle" : "in order"
    tooltip = head + " · every " + rotator.intervalMinutes + " min, " + mode
      + "\nClick: next · Middle: previous · Right: " + (paused ? "resume" : "pause")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    bar: root.bar
    text: root.paused ? root.glyphPaused : root.glyphImages
    useActiveColor: false
    foreground: root.paused ? Qt.darker(root.contentFg, 1.9) : root.contentFg
    tooltipText: root.tooltip
    onTooltipHoveredChanged: if (tooltipHovered) root.refreshTooltip()
    onPressed: function(buttonCode) {
      if (!root.rotator) return
      if (buttonCode === Qt.RightButton) root.rotator.togglePause()
      else if (buttonCode === Qt.MiddleButton) root.rotator.previous()
      else root.rotator.next()
      root.refreshTooltip()
    }
    onWheelMoved: function(delta) {
      if (!root.rotator) return
      if (delta > 0) root.rotator.previous()
      else root.rotator.next()
    }
  }

  Component.onCompleted: refreshTooltip()
}
