# Orbit Voice Shortcut

The generated `Orbit Voice.shortcut` is the external entry point for Orbit
Mini hands-free mode. It performs the public Shortcuts action **Get Current
App**, then invokes the shipped `Start Orbit Mini Hands-Free` AppIntent from
`net.opik.orbit.mini`.

Mini deliberately does not receive or restore a previous-app reference. The
repository's proven architecture assigns that responsibility to a separate
iOS Personal Automation, and does not use private scene APIs or a readiness
handshake.

After importing the signed artifact on iPhone, create the automation manually:

1. Shortcuts → Automation → New Personal Automation → **App**.
2. Choose **Orbit Mini**, select **Is Opened**, and disable confirmation if
   desired.
3. Add the owner's existing previous-app return action/shortcut, if present.

Portable `.shortcut` files cannot export an iOS Personal Automation trigger,
and this repository contains no proven persistent `ORBIT_HOME`/previous-app
storage action. The artifact therefore does not invent one or claim that an
independent automation can inherit a transient `Get Current App` value.
