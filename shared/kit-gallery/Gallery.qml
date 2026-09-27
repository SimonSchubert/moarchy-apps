import QtQuick
import "kit"
import "kit/Glyphs.js" as KG

App {
  id: root
  appId: "org.moarchy.kitgallery"
  title: "Kit"
  caption: "shared/kit"
  subtitle: compact ? "Phone layout" : "Desktop layout"
  windowWidth: 1100
  windowHeight: 760

  store: Store { name: "moarchy-kitgallery" }

  tabs: [
    { key: "controls", label: "Controls", glyph: KG.check },
    { key: "lists", label: "Lists", glyph: KG.sort },
    { key: "colours", label: "Colours", glyph: KG.star }
  ]

  actions: Component {
    Row {
      IconButton { app: root; glyph: KG.info; label: "Toast"; onClicked: root.toast("A toast") }
      IconButton { app: root; glyph: KG.remove; label: "Dialog"; onClicked: ask.open() }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Every widget in shared/kit"
      AppearanceSection { app: root }
      KeysSection { app: root; keys: [["1 – 3", "Pages"], [",", "Settings"], ["Esc", "Back"]] }
    }
  }

  page: Component {
    Item {
      PageHeader { id: head; app: root; width: parent.width; title: "A pushed page"; subtitle: "Back goes back" }
      EmptyState {
        anchors.centerIn: parent
        app: root
        glyph: KG.info
        title: "Nothing here"
        text: "An empty state, with the button that does something about it."
        actionText: "Back"
        onAction: root.back()
      }
    }
  }

  Dialog {
    id: ask
    app: root
    title: "Delete this?"
    text: "A dialog: a sheet on a phone, a card on a desktop."
    acceptText: "Delete"
    destructive: true
    onAccepted: root.toast("Deleted", "Undo", function () { root.toast("Undone") })
  }

  Flickable {
    anchors.fill: parent
    visible: root.tab === "controls"
    contentHeight: controls.implicitHeight + 32
    clip: true
    Column {
      id: controls
      x: root.ui.gutter
      y: 8
      width: Math.min(parent.width - root.ui.gutter * 2, 640)
      spacing: 18
      Flow {
        width: parent.width
        spacing: 10
        Button { app: root; text: "Primary"; primary: true }
        Button { app: root; text: "Plain" }
        Button { app: root; text: "With glyph"; glyph: KG.plus }
        Button { app: root; text: "Active"; active: true }
        Button { app: root; text: "Destructive"; primary: true; tint: root.ui.bad }
        Button { app: root; text: "Disabled"; enabled: false }
      }
      Flow {
        width: parent.width
        spacing: 8
        Chip { app: root; text: "Chosen"; selected: true }
        Chip { app: root; text: "Not" }
        Chip { app: root; text: "Glyph"; glyph: KG.star }
        IconButton { app: root; glyph: KG.search; label: "Search" }
        IconButton { app: root; glyph: KG.star; label: "Active"; active: true }
        Spinner { app: root }
      }
      SearchField { app: root; width: parent.width }
      TextField { app: root; width: parent.width; label: "A field"; placeholder: "Type here" }
      TextArea { app: root; width: parent.width; implicitHeight: 110; placeholder: "Several lines" }
      Toggle { id: tg; app: root; width: parent.width; text: "A switch"; note: "With a note under it"; onToggled: function (c) { checked = c } }
      Button { app: root; text: "Push a page"; onClicked: root.push({ kind: "page" }) }
    }
  }

  Flickable {
    anchors.fill: parent
    visible: root.tab === "lists"
    contentHeight: lists.implicitHeight + 32
    clip: true
    Column {
      id: lists
      x: root.ui.gutter
      y: 8
      width: Math.min(parent.width - root.ui.gutter * 2, 640)
      spacing: 14
      Card {
        app: root
        width: parent.width
        title: "A card"
        glyph: KG.info
        trailing: "12"
        ListRow { app: root; width: parent.width; glyph: KG.star; title: "A row"; text: "With a line under it"; chevron: true }
        ListRow { app: root; width: parent.width; glyph: KG.history; title: "Selected"; text: "The pane beside shows it"; selected: true; trailing: "3 min" }
        ListRow { app: root; width: parent.width; title: "No glyph"; trailing: "42" }
      }
      Card { app: root; width: parent.width; title: "Clickable"; clickable: true; onClicked: root.toast("Card") ; Text { text: "The whole card is a way in"; color: root.ui.muted; font.family: root.ui.font; font.pixelSize: root.ui.fs.sm } }
      EmptyState { app: root; glyph: KG.search; title: "An empty state"; text: "What to do about it"; actionText: "Do it" }
    }
  }

  Flickable {
    anchors.fill: parent
    visible: root.tab === "colours"
    contentHeight: swatches.implicitHeight + 32
    clip: true
    Flow {
      id: swatches
      x: root.ui.gutter
      y: 8
      width: parent.width - root.ui.gutter * 2
      spacing: 10
      Repeater {
        model: ["bg", "surface", "surfaceHigh", "well", "text", "muted", "accent", "accentSoft", "selected", "border", "divider", "good", "warn", "bad"]
        delegate: Column {
          required property string modelData
          spacing: 4
          Rectangle {
            width: 96
            height: 56
            radius: root.ui.radius
            color: root.ui[modelData]
            border.width: 1
            border.color: root.ui.divider
          }
          Text { text: modelData; color: root.ui.muted; font.family: root.ui.font; font.pixelSize: root.ui.fs.xs }
        }
      }
    }
  }
}
