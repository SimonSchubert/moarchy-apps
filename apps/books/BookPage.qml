import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "OpenLibrary.js" as OL

// One book: its cover, who wrote it and when, how its readers rated it, your
// shelf for it, what it is about, where it is filed, and more by the same
// author. The list it was opened from had the title, the author and the
// cover, so those are on screen at once; the rest is three small questions.
//
// Narrow, the cover stands over a wash of its own colours and everything
// runs down under it. Wide, it is a column of its own on the left with your
// shelf under it, and the book reads beside it.
Item {
  id: root
  property var app
  property var book: null
  property var detail: null
  property var ratings: null
  property var counts: null
  property var entry: null
  property var more: null
  property bool loading: false
  property string error: ""
  signal authorOpened(var author)
  signal subjectOpened(string name)
  signal bookOpened(var book)
  signal retry()

  readonly property bool wide: flick.width >= 880
  readonly property real sideWidth: wide ? Math.min(300, flick.width * 0.28) : 0
  readonly property real mainX: wide ? app.ui.gutter + sideWidth + 36 : app.ui.gutter
  readonly property real mainWidth: Math.min(wide ? flick.width - mainX - app.ui.gutter : flick.width - 2 * app.ui.gutter, 760)
  readonly property string title: detail && detail.title ? detail.title : book ? book.title : ""
  readonly property string subtitle: detail && detail.subtitle ? detail.subtitle : book ? book.subtitle || "" : ""
  // The cover the list showed, else the work's own first.
  readonly property var shown: book ? Object.assign({}, book, { title: title, cover: book.cover || (detail ? detail.cover : 0) }) : null
  readonly property var authors: root.app.authorsOf(book, detail)
  readonly property real average: ratings && ratings.count > 0 ? ratings.average : book ? book.rating : 0
  readonly property real ratingCount: ratings ? ratings.count : book ? book.ratings : 0
  property bool expanded: false

  onBookChanged: { expanded = false; flick.contentY = 0 }

  PageHeader {
    id: head
    width: parent.width
    app: root.app
    title: "Book"
    subtitle: root.title
    IconButton {
      app: root.app
      glyph: root.entry && root.entry.shelf === "want" ? G.wanted : G.want
      color: root.entry && root.entry.shelf === "want" ? root.app.ui.accent : root.app.ui.text
      label: root.entry && root.entry.shelf === "want" ? "Off Want to read" : "Want to read"
      onClicked: if (root.book) root.app.shelve(root.book, "want")
    }
    IconButton {
      app: root.app
      glyph: G.copy
      label: "Copy the Open Library link"
      onClicked: root.app.copyLink(root.book ? OL.workWeb(root.book.id) : "")
    }
    IconButton {
      app: root.app
      glyph: KG.open
      label: "Open on openlibrary.org"
      onClicked: if (root.book) Qt.openUrlExternally(OL.workWeb(root.book.id))
    }
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: moreShelf.y + (moreShelf.visible ? moreShelf.height : 0) + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // ------------------------------------------------ narrow: the cover on its wash
    Item {
      id: band
      visible: !root.wide
      width: flick.width
      height: visible ? heroCover.height + 44 : 0
      clip: true
      Rectangle { anchors.fill: parent; color: root.app.ui.surface }
      // The smallest cover Open Library has, stretched across the band: a
      // blur for nothing, in the book's own colours.
      Image {
        anchors.fill: parent
        visible: root.shown && root.shown.cover > 0
        source: visible ? root.app.coverSource(root.shown.cover, "S") : ""
        fillMode: Image.PreserveAspectCrop
        // Decoded at a few pixels and stretched: nothing of the lettering
        // is left, only its colours.
        sourceSize: Qt.size(6, 9)
        asynchronous: true
        smooth: true
        opacity: status === Image.Ready ? (root.app.ui.dark ? 0.32 : 0.4) : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: root.app.ui.alpha(root.app.ui.bg, 0.25) }
          GradientStop { position: 1.0; color: root.app.ui.bg }
        }
      }
      Cover {
        id: heroCover
        anchors.horizontalCenter: parent.horizontalCenter
        y: 22
        width: Math.min(176, flick.width * 0.46)
        height: Math.round(width * 3 / 2)
        app: root.app
        book: root.shown
        size: "L"
      }
    }

    // ------------------------------------------------ wide: the side column
    Column {
      id: side
      visible: root.wide
      x: root.app.ui.gutter
      y: 24
      width: root.sideWidth
      spacing: 18
      Cover {
        width: parent.width
        height: Math.round(width * 3 / 2)
        app: root.app
        book: root.shown
        size: "L"
      }
      ShelfActions {
        width: parent.width
        app: root.app
        book: root.book
        entry: root.entry
        stacked: true
      }
    }

    // ------------------------------------------------ the book
    Column {
      id: main
      x: root.mainX
      y: root.wide ? 24 : band.height + 2
      width: root.mainWidth
      spacing: 18

      // What it is and who wrote it.
      Column {
        width: parent.width
        spacing: 6
        Text {
          width: parent.width
          horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
          wrapMode: Text.Wrap
          text: root.title
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.wide ? root.app.ui.fs.xxl - 4 : root.app.ui.fs.xl
          font.weight: Font.Bold
          lineHeight: 1.08
        }
        Text {
          width: parent.width
          visible: root.subtitle !== ""
          horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
          wrapMode: Text.Wrap
          text: root.subtitle
          color: root.app.ui.text
          opacity: 0.8
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md + 1
        }
        Item { width: 1; height: 2 }
        // Each author a link to their page.
        Text {
          id: byWho
          width: parent.width
          horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          linkColor: root.app.ui.accent
          text: root.authors.length === 0 ? (root.loading ? "…" : "Unknown author")
            : root.authors.map(function (a) {
                var name = String(a.name).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                return OL.isAuthor(a.id) ? "<a href=\"" + a.id + "\"><b>" + name + "</b></a>" : "<b>" + name + "</b>"
              }).join(", ")
          color: root.authors.length ? root.app.ui.accent : root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md + 1
          onLinkActivated: function (link) {
            for (var i = 0; i < root.authors.length; i++)
              if (root.authors[i].id === link) { root.authorOpened(root.authors[i]); return }
          }
          HoverHandler {
            enabled: !root.app.compact
            cursorShape: byWho.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
          }
        }
        Text {
          width: parent.width
          horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
          wrapMode: Text.Wrap
          text: OL.facts(root.book, root.detail).join("  ·  ")
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }

      // How it was rated, and how many have it on a shelf.
      Rectangle {
        width: parent.width
        height: ratingRow.height + 24
        radius: root.app.ui.radius
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.line
        Row {
          id: ratingRow
          x: 14
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 28
          spacing: 0
          Repeater {
            model: [
              { big: root.average > 0 ? OL.rating(root.average) : "–", small: root.ratingCount > 0 ? OL.plural(root.ratingCount, "rating") : "no ratings", stars: true },
              { big: root.counts ? OL.count(root.counts.want) : root.book && root.book.wants ? OL.count(root.book.wants) : "–", small: root.app.compact ? "to read" : "want to read" },
              { big: root.counts ? OL.count(root.counts.reading) : "–", small: "reading" },
              { big: root.counts ? OL.count(root.counts.read) : root.book && root.book.reads ? OL.count(root.book.reads) : "–", small: "have read" }
            ]
            delegate: Item {
              id: stat
              required property var modelData
              required property int index
              width: ratingRow.width * (index === 0 ? 0.34 : 0.22)
              height: statCol.implicitHeight
              Rectangle {
                visible: stat.index > 0
                x: -1
                width: 1
                height: parent.height
                color: root.app.ui.divider
              }
              Column {
                id: statCol
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 8
                spacing: 3
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 6
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stat.modelData.big
                    color: root.app.ui.text
                    font.family: root.app.ui.font
                    font.pixelSize: root.app.ui.fs.lg + (stat.index === 0 ? 5 : 1)
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                  }
                  Icon {
                    visible: stat.index === 0 && root.average > 0
                    anchors.verticalCenter: parent.verticalCenter
                    app: root.app
                    text: KG.star
                    size: 16
                    color: root.app.ui.warn
                  }
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: stat.modelData.small
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.compact ? 10 : root.app.ui.fs.xs
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }

      // Narrow: your shelf here, under the facts.
      ShelfActions {
        visible: !root.wide
        width: parent.width
        app: root.app
        book: root.book
        entry: root.entry
      }

      // Something went wrong with the rest of it.
      Row {
        visible: root.error !== "" && !root.loading
        spacing: 12
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(main.width - retryBtn.width - 12, implicitWidth)
          wrapMode: Text.Wrap
          text: root.error
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
        Button { id: retryBtn; app: root.app; text: "Try again"; onClicked: root.retry() }
      }

      // ------------------------------------------------ about
      Column {
        width: parent.width
        spacing: 8
        visible: about.text !== "" || root.loading
        SectionTitle { app: root.app; text: "About" }
        Spinner { visible: root.loading && about.text === ""; running: visible; app: root.app; size: 20 }
        Text {
          id: about
          width: parent.width
          wrapMode: Text.Wrap
          text: root.detail ? root.detail.description : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          lineHeight: 1.3
          maximumLineCount: root.expanded ? 400 : (root.wide ? 12 : 9)
          elide: Text.ElideRight
        }
        Button {
          visible: about.truncated || root.expanded
          app: root.app
          text: root.expanded ? "Less" : "More"
          glyph: root.expanded ? KG.chevronDown : KG.chevronRight
          onClicked: root.expanded = !root.expanded
        }
      }

      // The first lines, where somebody typed them in.
      Rectangle {
        visible: root.detail !== null && root.detail.excerpt !== ""
        width: parent.width
        height: quoteText.implicitHeight + 28
        color: "transparent"
        Rectangle { width: 3; height: parent.height; color: root.app.ui.accent }
        Icon {
          x: 16
          y: 12
          app: root.app
          text: G.quote
          size: 18
          color: root.app.ui.alpha(root.app.ui.accent, 0.7)
        }
        Text {
          id: quoteText
          x: 42
          y: 14
          width: parent.width - 52
          wrapMode: Text.Wrap
          text: root.detail ? root.detail.excerpt : ""
          color: root.app.ui.text
          opacity: 0.85
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.italic: true
          lineHeight: 1.3
        }
      }

      // ------------------------------------------------ where it is filed
      Column {
        width: parent.width
        spacing: 10
        visible: root.detail !== null && root.detail.subjects.length > 0
        SectionTitle { app: root.app; text: "Subjects" }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: root.detail ? root.detail.subjects : []
            delegate: Chip {
              required property string modelData
              app: root.app
              text: modelData
              glyph: G.tag
              hpad: 16
              onClicked: root.subjectOpened(modelData)
            }
          }
        }
      }

      // ------------------------------------------------ the spread
      Column {
        width: Math.min(parent.width, 460)
        spacing: 10
        visible: root.ratings !== null && root.ratings.count > 0
        SectionTitle { app: root.app; text: "Ratings"; note: root.ratings ? OL.plural(root.ratings.count, "reader") : "" }
        RatingBars {
          width: parent.width
          app: root.app
          counts: root.ratings ? root.ratings.counts : [0, 0, 0, 0, 0]
        }
      }
    }

    // ------------------------------------------------ more by them
    Shelf {
      id: moreShelf
      readonly property var who: root.authors.length ? root.authors[0] : null
      readonly property var others: (root.more ? root.more.items : []).filter(function (b) { return !root.book || b.id !== root.book.id })
      visible: who !== null && (others.length > 0 || (root.more !== null && root.more.loading))
      y: Math.max(main.y + main.height, side.visible ? side.y + side.height : 0) + 30
      x: root.wide ? root.mainX - root.app.ui.gutter : 0
      width: root.wide ? flick.width - x : flick.width
      app: root.app
      title: who ? "More by " + who.name : ""
      items: others.slice(0, 16)
      loading: root.more !== null && root.more.loading
      coverWidth: root.app.compact ? 96 : 116
      onOpened: function (book) { root.bookOpened(book) }
      onSeeAllClicked: if (who) root.authorOpened(who)
    }
  }
}
