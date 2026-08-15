import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n

// City search and list for switching servers.
//
// The choice is per city, not per relay: the daemon already balances load within
// a city, and 91 cities fit a navigable list where 574 servers would not.
Column {
  id: root

  property var cities: []
  property string selectedCountry: ""
  property string selectedCity: ""
  property bool enabled: true

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  // The panel's PanelKeyCatcher uses Keys.priority BeforeItem and would swallow
  // the search field's keystrokes; the panel reads this to stay quiet while the
  // user types.
  readonly property bool searching: search.activeFocus

  property string query: ""
  readonly property var visibleCities: Model.filterCities(cities, query)

  signal citySelected(string countryCode, string cityCode)

  spacing: Style.space(8)

  PanelSectionHeader {
    text: I18n.t("server.title")
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  TextField {
    id: search
    width: parent.width
    placeholderText: I18n.t("server.search")
    foreground: root.foreground
    font.family: root.fontFamily
    enabled: root.enabled
    text: root.query

    onTextChanged: root.query = text
    Keys.onEscapePressed: {
      if (root.query !== "") { root.query = ""; return }
      focus = false
    }
  }

  Text {
    visible: root.cities.length === 0
    width: parent.width
    text: I18n.t("server.pending")
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Text {
    visible: root.cities.length > 0 && root.visibleCities.length === 0
    width: parent.width
    text: I18n.t("server.noMatch", { query: root.query })
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  // ListView rather than Repeater: there are dozens of cities, and its own
  // scrolling keeps the list from pushing the panel off screen.
  ListView {
    id: list
    width: parent.width
    height: Math.min(contentHeight, Style.space(220))
    visible: root.visibleCities.length > 0
    spacing: Style.space(2)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    model: root.visibleCities

    delegate: CityRow {
      required property var modelData
      width: ListView.view.width
      city: modelData
    }
  }

  component CityRow: CursorSurface {
    id: row
    property var city: null

    readonly property bool selected: Model.isSelectedCity(row.city, root.selectedCountry, root.selectedCity)

    current: selected
    foreground: root.foreground
    accent: root.accent
    implicitHeight: rowLayout.implicitHeight + Style.spacing.rowPaddingX

    // The CursorSurface contract: the mouse moves the cursor, color derives from
    // it. With no keyboard cursor in this list, hasCursor follows hover alone.
    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (!root.enabled || !row.city) return
        root.citySelected(row.city.countryCode, row.city.cityCode)
      }
    }

    hasCursor: hover.containsMouse && root.enabled

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Column {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          text: row.city ? row.city.city : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.selected
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          text: row.city ? row.city.country : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Text {
        text: row.city ? String(row.city.relayCount) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
