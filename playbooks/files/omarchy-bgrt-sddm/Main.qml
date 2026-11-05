// Omarchy BGRT login screen — managed by playbooks/system/bgrt-theme.yml.
//
// The SDDM counterpart of the omarchy-bgrt Plymouth theme
// (omarchy-bgrt.script): same black background, the firmware's own logo at
// the firmware's own yoffset, the password field 40px below it with the lock
// to its left, and the small Omarchy wordmark 30px below the field. Booting
// into this screen, nothing moves: the field the disk prompt used is where
// the login password goes.
//
// Login logic is Omarchy's stock greeter (default/sddm/omarchy/Main.qml):
// a password for the last user, into the uwsm session.
import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#000000"

  // From theme.conf, which the playbook writes from
  // /sys/firmware/acpi/bgrt/yoffset.
  readonly property int firmwareYOffset: parseInt(config.yoffset) || 0

  // Same gaps as omarchy-bgrt.script.
  readonly property int entryGapAbove: 40
  readonly property int entryGapBelow: 30

  property string currentUser: userModel.lastUser !== ""
    ? userModel.lastUser
    : (userModel.rowCount() > 0 ? userModel.data(userModel.index(0, 0), Qt.UserRole + 1) : "")
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  // Height of everything from the top of the logo to the bottom of the
  // wordmark. On a screen shorter than the firmware's layout assumed (a
  // second monitor, the --test-mode window), the stack moves up just enough
  // to stay whole instead of running off the bottom.
  readonly property int stackHeight: logo.height + entryGapAbove + entryBox.height + entryGapBelow + wordmark.height
  readonly property int logoY: Math.max(0, Math.min(firmwareYOffset, root.height - stackHeight))

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Image {
    id: logo
    source: "logo.png"
    x: Math.round((root.width - width) / 2)
    y: root.logoY
  }

  Item {
    id: entryBox
    width: entry.implicitWidth
    height: entry.implicitHeight
    x: Math.round((root.width - width) / 2)
    y: logo.y + logo.height + root.entryGapAbove

    Image {
      id: entry
      source: root.loginFailed ? "entry-failed.png" : "entry.png"
      anchors.fill: parent
    }

    // Plymouth draws at most 21 bullets, 7px wide, 12px apart, from 20px in.
    Row {
      anchors.left: parent.left
      anchors.leftMargin: 20
      anchors.verticalCenter: parent.verticalCenter
      spacing: 5

      Repeater {
        model: Math.min(password.text.length, 21)

        Image {
          source: root.loginFailed ? "bullet-failed.png" : "bullet.png"
          width: 7
          height: 7
        }
      }
    }

    TextInput {
      id: password
      anchors.fill: parent
      anchors.leftMargin: 20
      anchors.rightMargin: 20
      verticalAlignment: TextInput.AlignVCenter
      echoMode: TextInput.Password
      font.pixelSize: 24
      color: "transparent"
      selectionColor: "transparent"
      selectedTextColor: "transparent"
      cursorDelegate: Item {}
      focus: true

      onTextChanged: if (text.length > 0) root.loginFailed = false

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          sddm.login(root.currentUser, password.text, root.sessionIndex)
          event.accepted = true
        }
      }
    }
  }

  // omarchy-bgrt.script: 0.8 of the field's height, 84:96, 15px to its left.
  Image {
    id: lock
    source: root.loginFailed ? "lock-failed.png" : "lock.png"
    height: entryBox.height * 0.8
    width: height * 84 / 96
    x: entryBox.x - width - 15
    y: entryBox.y + (entryBox.height - height) / 2
    smooth: true
    mipmap: true
  }

  Image {
    id: wordmark
    source: "wordmark.png"
    x: Math.round((root.width - width) / 2)
    y: entryBox.y + entryBox.height + root.entryGapBelow
  }

  Component.onCompleted: password.forceActiveFocus()
}
