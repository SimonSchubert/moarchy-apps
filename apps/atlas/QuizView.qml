import QtQuick
import "kit"
import "Glyphs.js" as G
import "Countries.js" as C
import "Quiz.js" as Q

// The quiz, in three states: choosing a round, a question, and the score.
//
// The round itself is the panel's (app.round), so the page can be thrown away
// and built again -- a phone reclaiming memory, a tab switched -- without a
// question changing under anybody. `app.shownQuestion` is the question on
// screen; a pick reveals it, and Next moves on.
Item {
  id: root
  property var app

  readonly property var round: app.round
  readonly property int shownIndex: app.shownQuestion
  readonly property bool playing: round !== null && shownIndex < round.questions.length
  readonly property bool done: round !== null && !playing
  readonly property var question: playing ? round.questions[shownIndex] : null
  readonly property bool revealed: playing && round.picks.length > shownIndex
  readonly property string picked: revealed ? round.picks[shownIndex] : ""
  readonly property var answer: question ? app.country(question.answer) : null
  readonly property int column: Math.min(width - (app.compact ? 32 : 48), 620)

  Loader {
    anchors.fill: parent
    sourceComponent: root.playing ? questionPage : root.done ? scorePage : menuPage
  }

  // ------------------------------------------------------------ choosing

  Component {
    id: menuPage
    Flickable {
      contentWidth: width
      contentHeight: menu.implicitHeight + 40
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: menu
        x: (parent.width - width) / 2
        y: 12
        width: root.column
        spacing: 18

        Row {
          width: parent.width
          spacing: 14
          Icon {
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            text: G.quiz
            size: 34
            color: root.app.ui.accent
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 62
            spacing: 2
            Text {
              text: "Ten questions"
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xl
              font.weight: Font.Bold
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: root.app.stats.rounds === 0 ? "Four answers each, the wrong ones from next door."
                : root.app.stats.rounds + (root.app.stats.rounds === 1 ? " round" : " rounds") + " played, "
                  + Math.round(100 * root.app.stats.right / Math.max(1, root.app.stats.asked)) + "% right"
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
        }

        Column {
          width: parent.width
          spacing: 8
          SectionTitle { app: root.app; text: "Round" }
          Repeater {
            model: Q.MODES
            delegate: Rectangle {
              id: modeRow
              required property var modelData
              readonly property bool chosen: root.app.quizMode === modelData.key
              readonly property string best: Q.best(root.app.stats, modelData.key, root.app.quizScope)
              width: parent.width
              height: root.app.compact ? 62 : 58
              radius: root.app.ui.radius
              color: chosen ? root.app.ui.selected : modeMouse.pressed ? root.app.ui.pressed
                : modeMouse.containsMouse ? root.app.ui.hover : root.app.ui.surface
              border.width: chosen ? 2 : 1
              border.color: chosen ? root.app.ui.accent : root.app.ui.line
              Accessible.role: Accessible.RadioButton
              Accessible.name: modelData.label
              Icon {
                id: modeGlyph
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                text: modeRow.modelData.key === "capitals" ? G.capital : modeRow.modelData.key === "find" ? G.flagOutline : G.flag
                size: 20
                color: modeRow.chosen ? root.app.ui.accent : root.app.ui.muted
              }
              Column {
                anchors.left: modeGlyph.right
                anchors.leftMargin: 10
                anchors.right: bestText.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                  width: parent.width
                  text: modeRow.modelData.label
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.md
                  font.weight: Font.Bold
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: modeRow.modelData.note
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm - 1
                  elide: Text.ElideRight
                }
              }
              Row {
                id: bestText
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: modeRow.best !== ""
                Icon {
                  anchors.verticalCenter: parent.verticalCenter
                  app: root.app
                  text: G.trophyOutline
                  size: 14
                  width: 16
                  color: root.app.ui.warn
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modeRow.best
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                  font.weight: Font.Bold
                  font.features: ({ "tnum": 1 })
                }
              }
              MouseArea {
                id: modeMouse
                anchors.fill: parent
                hoverEnabled: !root.app.compact
                cursorShape: Qt.PointingHandCursor
                onClicked: root.app.store.set("quizMode", modeRow.modelData.key)
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: 8
          SectionTitle { app: root.app; text: "Where" }
          Flow {
            width: parent.width
            spacing: 6
            Repeater {
              model: ["world"].concat(root.app.regions)
              delegate: Chip {
                required property string modelData
                app: root.app
                text: modelData === "world" ? "World" : modelData
                selected: root.app.quizScope === modelData
                enabled: Q.playable(root.app.countries, modelData, root.app.quizMode)
                opacity: enabled ? 1 : 0.4
                onClicked: root.app.store.set("quizScope", modelData)
              }
            }
          }
        }

        Button {
          width: parent.width
          app: root.app
          primary: true
          glyph: G.quiz
          text: "Start"
          enabled: Q.playable(root.app.countries, root.app.quizScope, root.app.quizMode)
          onClicked: root.app.startQuiz()
        }
      }
    }
  }

  // ------------------------------------------------------------ a question

  Component {
    id: questionPage
    Item {
      Flickable {
        id: qFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        contentWidth: width
        contentHeight: qBody.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: qBody
          x: (parent.width - width) / 2
          y: 10
          width: root.column
          spacing: 16

          // Where the round is: a square per question, filled as it goes.
          Column {
            width: parent.width
            spacing: 8
            Item {
              width: parent.width
              height: 20
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "QUESTION " + (root.shownIndex + 1) + " / " + (root.round ? root.round.questions.length : 0)
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                font.weight: Font.Bold
                font.letterSpacing: root.app.ui.tracking
              }
              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Row {
                  spacing: 3
                  visible: Q.streak(root.round) >= 2
                  Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    app: root.app
                    text: G.streak
                    size: 14
                    width: 16
                    color: root.app.ui.warn
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(Q.streak(root.round))
                    color: root.app.ui.text
                    font.family: root.app.ui.font
                    font.pixelSize: root.app.ui.fs.sm
                    font.weight: Font.Bold
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: Q.score(root.round) + " right"
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                  font.weight: Font.Bold
                  font.features: ({ "tnum": 1 })
                }
              }
            }
            Row {
              id: track
              width: parent.width
              spacing: 4
              readonly property int n: root.round ? root.round.questions.length : 1
              Repeater {
                model: track.n
                delegate: Rectangle {
                  required property int index
                  readonly property bool answered: root.round && index < root.round.picks.length
                  width: (track.width - track.spacing * (track.n - 1)) / track.n
                  height: 6
                  radius: root.app.ui.radius > 0 ? 3 : 0
                  color: !answered ? (index === root.shownIndex ? root.app.ui.accentSoft : root.app.ui.well)
                    : Q.right(root.round, index) ? root.app.ui.good : root.app.ui.bad
                }
              }
            }
          }

          // The prompt.
          Rectangle {
            width: parent.width
            height: prompt.implicitHeight + 36
            radius: root.app.ui.radius
            color: root.app.ui.surface
            border.width: 1
            border.color: root.app.ui.line
            Column {
              id: prompt
              x: 18
              y: 18
              width: parent.width - 36
              spacing: 14
              Flag {
                visible: root.round && root.round.mode !== "find"
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.round && root.round.mode === "capitals" ? Math.min(parent.width, 150) : Math.min(parent.width, root.app.compact ? 200 : 300)
                height: Math.round(width * 0.62)
                decodeWidth: 320
                app: root.app
                code: root.question ? root.question.answer : ""
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: !root.round || !root.answer ? ""
                  : root.round.mode === "flags" ? "Whose flag is this?"
                  : root.round.mode === "find" ? "Which is the flag of"
                  : "What is the capital of"
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.md
              }
              Text {
                visible: root.round && root.round.mode !== "flags"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.answer ? root.answer.name + "?" : ""
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xl
                font.weight: Font.Bold
              }
            }
          }

          // Four answers: rows of words, or a square of flags.
          Grid {
            id: options
            width: parent.width
            readonly property bool flags: root.round !== null && root.round.mode === "find"
            columns: flags ? 2 : 1
            spacing: 8
            Repeater {
              model: root.question ? root.question.options : []
              delegate: Rectangle {
                id: opt
                required property string modelData
                required property int index
                readonly property var country: root.app.country(modelData)
                readonly property bool isAnswer: root.question && modelData === root.question.answer
                readonly property bool isPicked: root.picked === modelData
                readonly property string state3: !root.revealed ? "" : isAnswer ? "right" : isPicked ? "wrong" : "other"
                readonly property color hue: state3 === "right" ? root.app.ui.good : state3 === "wrong" ? root.app.ui.bad : root.app.ui.line
                width: (options.width - options.spacing * (options.columns - 1)) / options.columns
                height: options.flags ? Math.round(width * 0.62) + 20 : 48
                radius: root.app.ui.radius
                color: state3 === "right" || state3 === "wrong" ? Qt.tint(root.app.ui.surface, root.app.ui.alpha(hue, 0.22))
                  : optMouse.pressed ? Qt.tint(root.app.ui.surface, root.app.ui.pressed)
                  : optMouse.containsMouse && !root.revealed ? Qt.tint(root.app.ui.surface, root.app.ui.hover) : root.app.ui.surface
                border.width: state3 === "right" || state3 === "wrong" ? 2 : 1
                border.color: hue
                opacity: state3 === "other" ? 0.55 : 1
                Accessible.role: Accessible.Button
                Accessible.name: options.flags ? "Flag " + (index + 1) : (country ? (root.round.mode === "capitals" ? C.capital(country) : country.name) : "")

                // The key that answers, on a keyboard.
                Text {
                  visible: !root.app.compact && !options.flags
                  x: 14
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(opt.index + 1)
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                  font.weight: Font.Bold
                }
                Text {
                  visible: !options.flags
                  anchors.left: parent.left
                  anchors.leftMargin: root.app.compact ? 16 : 38
                  anchors.right: mark.left
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  text: !opt.country ? "" : root.round.mode === "capitals" ? C.capital(opt.country) : opt.country.name
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.md + 1
                  font.weight: Font.Bold
                  elide: Text.ElideRight
                }
                Flag {
                  visible: options.flags
                  anchors.fill: parent
                  anchors.margins: 10
                  decodeWidth: 320
                  app: root.app
                  code: opt.modelData
                }
                // A mark as well as a colour: right and wrong are not only green
                // and red.
                Rectangle {
                  id: mark
                  visible: opt.state3 === "right" || opt.state3 === "wrong"
                  anchors.right: parent.right
                  anchors.rightMargin: options.flags ? 6 : 10
                  anchors.top: options.flags ? parent.top : undefined
                  anchors.topMargin: 6
                  anchors.verticalCenter: options.flags ? undefined : parent.verticalCenter
                  width: 26
                  height: 26
                  radius: 13
                  color: root.app.ui.surface
                  Icon {
                    anchors.centerIn: parent
                    app: root.app
                    text: opt.state3 === "right" ? G.right : G.wrong
                    size: 22
                    color: opt.hue
                  }
                }
                MouseArea {
                  id: optMouse
                  anchors.fill: parent
                  enabled: !root.revealed
                  hoverEnabled: !root.app.compact
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.app.answerQuiz(opt.modelData)
                }
              }
            }
          }

          // What the answer was, once there is one, and the way on: here on a
          // desktop, pinned to the bottom on a phone, where a thumb is.
          Loader {
            width: parent.width
            active: root.revealed && !root.app.compact
            visible: active
            sourceComponent: revealBlock
          }
        }
      }

      Rectangle {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.revealed && root.app.compact ? footerBody.height + 24 : 0
        visible: height > 0
        color: root.app.ui.bg
        Rectangle { width: parent.width; height: 1; color: root.app.ui.line }
        Loader {
          id: footerBody
          x: (parent.width - width) / 2
          y: 12
          width: root.column
          active: root.revealed && root.app.compact
          sourceComponent: revealBlock
        }
      }
    }
  }

  // The answer, said, and Next.
  Component {
    id: revealBlock
    Column {
      spacing: 12
      Row {
        width: parent.width
        spacing: 12
        Flag {
          anchors.verticalCenter: parent.verticalCenter
          width: 48
          height: 32
          app: root.app
          code: root.answer ? root.answer.code : ""
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 60
          spacing: 1
          Text {
            width: parent.width
            text: (root.picked === (root.question ? root.question.answer : "") ? "Right: " : "It was ") + (root.answer ? root.answer.name : "")
            color: root.picked === (root.question ? root.question.answer : "") ? root.app.ui.good : root.app.ui.bad
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.Bold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.answer ? [C.capital(root.answer), root.answer.subregion || root.answer.region, C.people(root.answer.population)].filter(function (x) { return x }).join("  ·  ") : ""
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm - 1
            elide: Text.ElideRight
          }
        }
      }
      Button {
        width: parent.width
        app: root.app
        primary: true
        text: root.round && root.shownIndex + 1 >= root.round.questions.length ? "See the score" : "Next"
        onClicked: root.app.nextQuestion()
      }
    }
  }

  // ------------------------------------------------------------ the score

  Component {
    id: scorePage
    Flickable {
      contentWidth: width
      contentHeight: sBody.implicitHeight + 40
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: sBody
        x: (parent.width - width) / 2
        y: 16
        width: root.column
        spacing: 18

        Rectangle {
          width: parent.width
          height: scoreCol.implicitHeight + 44
          radius: root.app.ui.radius
          color: root.app.ui.surface
          border.width: 1
          border.color: root.app.ui.line
          Column {
            id: scoreCol
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: 6
            Icon {
              anchors.horizontalCenter: parent.horizontalCenter
              app: root.app
              text: root.app.newBest ? G.trophy : G.quiz
              size: 34
              color: root.app.newBest ? root.app.ui.warn : root.app.ui.accent
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Q.score(root.round) + " / " + (root.round ? root.round.questions.length : 0)
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xxl + 12
              font.weight: Font.Bold
              font.features: ({ "tnum": 1 })
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Q.verdict(Q.score(root.round), root.round ? root.round.questions.length : 0)
              color: root.app.ui.accent
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.lg
              font.weight: Font.Bold
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: !root.round ? ""
                : Q.mode(root.round.mode).label + ", " + (root.round.scope === "world" ? "the world" : root.round.scope)
                  + (root.app.newBest ? "  ·  a new best" : Q.best(root.app.stats, root.round.mode, root.round.scope) ? "  ·  best " + Q.best(root.app.stats, root.round.mode, root.round.scope) : "")
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
        }

        Row {
          width: parent.width
          spacing: 8
          Button {
            width: (parent.width - 8) / 2
            app: root.app
            primary: true
            glyph: G.again
            text: "Again"
            onClicked: root.app.startQuiz()
          }
          Button {
            width: (parent.width - 8) / 2
            app: root.app
            text: "Change"
            onClicked: root.app.leaveQuiz()
          }
        }

        Column {
          width: parent.width
          spacing: 4
          visible: Q.misses(root.round).length > 0
          SectionTitle { app: root.app; text: "To look at again"; note: String(Q.misses(root.round).length) }
          Repeater {
            model: Q.misses(root.round)
            delegate: Rectangle {
              id: miss
              required property string modelData
              readonly property var country: root.app.country(modelData)
              width: parent.width
              height: root.app.compact ? 56 : 50
              radius: root.app.ui.radius
              color: missMouse.pressed ? root.app.ui.pressed : missMouse.containsMouse ? root.app.ui.hover : "transparent"
              Flag {
                id: missFlag
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                height: 28
                app: root.app
                code: miss.modelData
              }
              Column {
                anchors.left: missFlag.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  width: parent.width
                  text: miss.country ? miss.country.name : miss.modelData
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.md
                  font.weight: Font.Bold
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: miss.country ? C.line(miss.country) : ""
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm - 1
                  elide: Text.ElideRight
                }
              }
              MouseArea {
                id: missMouse
                anchors.fill: parent
                hoverEnabled: !root.app.compact
                cursorShape: Qt.PointingHandCursor
                onClicked: root.app.showCountry(miss.modelData)
              }
            }
          }
        }
      }
    }
  }
}
