// Omarchy BGRT login screen — managed by playbooks/system/bgrt-theme.yml.
//
// The SDDM counterpart of the omarchy-bgrt Plymouth theme
// (omarchy-bgrt.script): same black background, the firmware's own logo at
// the firmware's own yoffset, the password field 40px below it with the lock
// to its left, and the small Omarchy wordmark 30px below the field. Booting
// into this screen, nothing moves: the field the disk prompt used is where
// the login password goes.
//
// Login logic is omarchy-multiuser's greeter
// (/usr/share/sddm/themes/omarchy-multiuser/Main.qml), so this theme can
// replace it on a machine with several people: a password alone, tried for
// the last account and then each other one until one logs in (Password.js;
// omarchy-mu-login-match ends an attempt on the wrong account at once), and
// the power actions at the bottom, by click or F key (Power.js). Without
// omarchy-multiuser, on a single-user machine, that is Omarchy's stock
// greeter: a password for the last user, into the uwsm session.
//
// As it comes up, it logs in by itself whoever unlocked the disk at this boot, as
// omarchy-multiuser's greeter does from 0.12.0 (omarchy-mu-login-select chooses,
// omarchy-mu-login-once lets that one login through), so that desktop gets a
// console of its own and switching users needs no logout.
pragma ComponentBehavior: Bound

import QtQuick 2.15
import QtQuick.Window 2.15
import SddmComponents 2.0
import "Strings.js" as Strings
import "Password.js" as Password
import "Power.js" as Power

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#000000"

  readonly property color textColor: "#ffffff"
  readonly property string localeName: Qt.locale().name
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  // From theme.conf, which the playbook writes from
  // /sys/firmware/acpi/bgrt/yoffset.
  readonly property int firmwareYOffset: parseInt(config.yoffset) || 0

  // Same gaps as omarchy-bgrt.script.
  readonly property int entryGapAbove: 40
  readonly property int entryGapBelow: 30

  // Filled from userModel by the Repeater below.
  property var userSlots: ({})
  property var userNames: []
  property bool loginFailed: false
  property var attemptUsers: []
  property int attempt: 0
  property string pending: ""
  property bool awaiting: false
  property int resends: 0
  // SDDM sends LoginFailed twice for one failure. The second is consumed as such
  // even if it arrives after the next account was sent, so it is never taken for
  // that account's answer.
  property int duplicates: 0
  // The greeter's own try, as it comes up, at the login omarchy-mu-login-select
  // chose (omarchy-mu-login-once), and an Enter pressed meanwhile.
  property bool autoAttempt: false
  property bool loginQueued: false
  readonly property var powerActions: Power.available(powerCaps)
  // All false until the daemon tells SDDM what the machine can do.
  readonly property var powerCaps: ({
    suspend: sddm.canSuspend,
    hibernate: sddm.canHibernate,
    reboot: sddm.canReboot,
    powerOff: sddm.canPowerOff
  })
  // The action waiting for a confirmation, or null.
  property var pendingPower: null
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  // Height of everything from the top of the logo to the bottom of the
  // wordmark, plus the power row under it. On a screen shorter than the
  // firmware's layout assumed (a second monitor, the --test-mode window), the
  // stack moves up just enough to stay whole instead of running off the bottom.
  readonly property int stackHeight: logo.height + entryGapAbove + entryBox.height + entryGapBelow + wordmark.height
  readonly property int logoY: Math.max(0, Math.min(firmwareYOffset, root.height - stackHeight - 72))

  function addUser(index, name) {
    userSlots[index] = name
    userNames = Object.keys(userSlots).map(Number).sort(function (a, b) { return a - b })
      .map(function (key) { return userSlots[key] })
  }

  function login() {
    attemptUsers = Password.candidates(userModel.lastUser, userNames)
    if (attemptUsers.length === 0 || password.text.length === 0)
      return
    pending = password.text
    attempt = 0
    resends = 0
    send()
  }

  function failLogin() {
    pending = ""
    awaiting = false
    password.text = ""
    loginFailed = true
    password.forceActiveFocus()
  }

  function send() {
    awaiting = true
    sddm.login(attemptUsers[attempt], pending, root.sessionIndex)
    unanswered.restart()
  }

  // An empty password for SDDM's last user. omarchy-mu-login-select left a pass for
  // it if the disk was unlocked with that user's password at this boot; without one,
  // PAM turns it down at once, and nothing shows.
  function tryAutoLogin() {
    var user = Password.autoLoginUser(userModel.lastUser)
    if (user === "")
      return
    autoAttempt = true
    awaiting = true
    sddm.login(user, "", root.sessionIndex)
    unanswered.restart()
  }

  function endAutoLogin() {
    autoAttempt = false
    awaiting = false
    unanswered.stop()
    if (loginQueued) {
      loginQueued = false
      queuedLogin.start()
    }
  }

  function requestPower(action) {
    if (action.confirm) {
      pendingPower = action
      powerTimeout.restart()
    } else {
      runPower(action)
    }
  }

  // Nothing typed stays in the box across a suspend.
  function runPower(action) {
    pendingPower = null
    password.text = ""
    sddm[action.id]()
  }

  // Escape and the power keys.
  function handleCommonKey(event) {
    if (pendingPower !== null) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        // Enter still held from before isn't an answer to the question.
        if (!event.isAutoRepeat)
          runPower(pendingPower)
        event.accepted = true
        return true
      }
      if (event.key === Qt.Key_Escape) {
        pendingPower = null
        event.accepted = true
        return true
      }
      // Anything else is someone logging in: it goes on as usual.
      if (event.key < Qt.Key_F1 || event.key > Qt.Key_F4)
        pendingPower = null
    }
    if (event.key === Qt.Key_Escape) {
      password.text = ""
    } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F4) {
      // Held down, the key would run it again as the machine wakes up.
      var action = Power.forFKey(powerCaps, event.key - Qt.Key_F1 + 1)
      if (action !== null && !event.isAutoRepeat)
        requestPower(action)
    } else {
      return false
    }
    event.accepted = true
    return true
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      if (root.duplicates > 0) {
        root.duplicates--
        return
      }
      root.duplicates = 1
      pairWindow.restart()
      if (!root.awaiting)
        return
      root.awaiting = false
      unanswered.stop()
      if (root.autoAttempt) {
        root.endAutoLogin()
        return
      }
      if (root.pending !== "" && root.attempt + 1 < root.attemptUsers.length) {
        root.attempt++
        root.resends = 0
        nextAttempt.start()
        return
      }
      root.failLogin()
    }
    function onLoginSucceeded() {
      root.autoAttempt = false
      root.awaiting = false
      unanswered.stop()
      root.pending = ""
      root.loginFailed = false
    }
  }

  // SDDM reports a failure before its helper has exited, and silently drops a login
  // sent before then, so the next account waits a moment; an attempt still unanswered
  // after pam_unix's failure delay was dropped, and is sent again, a few times at most.
  Timer {
    id: nextAttempt
    interval: 300
    onTriggered: root.send()
  }

  Timer {
    id: unanswered
    interval: 5000
    onTriggered: {
      if (root.autoAttempt) {
        root.endAutoLogin()
        return
      }
      if (root.pending === "")
        return
      if (root.resends >= 3) {
        root.failLogin()
        return
      }
      root.resends++
      root.send()
    }
  }

  // As nextAttempt: SDDM drops a login sent before the last one's helper is gone.
  Timer {
    id: queuedLogin
    interval: 300
    onTriggered: root.login()
  }

  Timer {
    id: pairWindow
    interval: 1000
    onTriggered: root.duplicates = 0
  }

  // userModel's name role is only reachable from a delegate, so each reports its row.
  Repeater {
    model: userModel
    delegate: Item {
      required property int index
      required property string name
      Component.onCompleted: root.addUser(index, name)
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
        if (root.handleCommonKey(event))
          return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.pending === "" && !root.awaiting)
            root.login()
          else if (root.autoAttempt)
            root.loginQueued = true
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

  // Clicks here leave the keyboard focus in the text field.
  component PowerLink: Item {
    id: link
    property string text
    signal clicked()
    width: linkLabel.implicitWidth
    height: linkLabel.implicitHeight

    Text {
      id: linkLabel
      text: link.text
      color: root.textColor
      opacity: linkMouse.containsMouse ? 1.0 : 0.55
      font.family: root.fontFamily
      font.pixelSize: 16
    }

    MouseArea {
      id: linkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
  }

  // A question nobody answered doesn't wait for the next Enter.
  Timer {
    id: powerTimeout
    interval: 10000
    onTriggered: root.pendingPower = null
  }

  Row {
    visible: root.pendingPower === null
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 24
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 32

    Repeater {
      model: root.powerActions

      delegate: PowerLink {
        required property var modelData
        text: modelData.icon + " " + Strings.t(root.localeName, modelData.label) + " [F" + modelData.fkey + "]"
        onClicked: root.requestPower(modelData)
      }
    }
  }

  Row {
    visible: root.pendingPower !== null
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 24
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 32

    Text {
      text: root.pendingPower !== null
            ? root.pendingPower.icon + " " + Strings.t(root.localeName, root.pendingPower.confirm) : ""
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: 16
    }

    PowerLink {
      text: Strings.t(root.localeName, "confirm") + " [Enter]"
      onClicked: root.runPower(root.pendingPower)
    }

    PowerLink {
      text: Strings.t(root.localeName, "cancel") + " [Esc]"
      onClicked: root.pendingPower = null
    }
  }

  // Going to another console and back takes the keyboard away, and Qt drops the
  // field's focus with it. Nothing gives it back when the keyboard returns, so typing
  // and the F keys went nowhere until the field was clicked.
  function restorePasswordFocus() {
    if (!password.activeFocus) password.forceActiveFocus()
  }
  Window.onActiveFocusItemChanged: Qt.callLater(restorePasswordFocus)

  Component.onCompleted: {
    password.forceActiveFocus()
    tryAutoLogin()
  }
}
