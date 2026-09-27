import QtQuick
import "kit"
import "Glyphs.js" as G

// A barcode that scanned cleanly and is not in the catalogue: the ordinary
// end of pointing the camera at a local brand nobody has photographed yet.
Item {
  id: root
  property var app
  property string code: ""
  EmptyState {
    anchors.centerIn: parent
    app: root.app
    glyph: G.missing
    title: "Not in Open Food Facts"
    text: root.code + " is a real barcode, and the catalogue has no product for it. Scan another."
  }
}
