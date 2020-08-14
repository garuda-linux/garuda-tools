---
componentName:  garuda

# This selects between different welcome texts. When false, uses
# the traditional "Welcome to the %1 installer.", and when true,
# uses "Welcome to the Calamares installer for %1." This allows
# to distinguish this installer from other installers for the
# same distribution.
welcomeStyleCalamares:   ${welcomestyle}

# Should the welcome image (productWelcome, below) be scaled
# up beyond its natural size? If false, the image does not grow
# with the window but remains the same size throughout (this
# may have surprising effects on HiDPI monitors).
welcomeExpandingLogo:   ${welcomelogo}

# Size and expansion policy for Calamares.
#  - "normal" or unset, expand as needed, use *windowSize*
#  - "fullscreen", start as large as possible, ignore *windowSize*
#  - "noexpand", never expand, use *windowSize*
windowExpanding:    ${windowexp}

# Size of Calamares window, expressed as w,h. Both w and h
# may be either pixels (suffix px) or font-units (suffix em).
#   e.g.    "800px,600px"
#           "60em,480px"
# This setting is ignored if "fullscreen" is selected for
# *windowExpanding*, above. If not set, use constants defined
# in CalamaresUtilsGui, 800x520.
windowSize: ${windowsize}

# Placement of Calamares window. Either "center" or "free".
# Whether "center" actually works does depend on the window
# manager in use (and only makes sense if you're not using
# *windowExpanding* set to "fullscreen").
windowPlacement: ${windowplacement}

# These are strings shown to the user in the user interface.
# There is no provision for translating them -- since they
# are names, the string is included as-is.
#
# The four Url strings are the Urls used by the buttons in
# the welcome screen, and are not shown to the user. Clicking
# on the "Support" button, for instance, opens the link supportUrl.
# If a Url is empty, the corresponding button is not shown.
#
# bootloaderEntryName is how this installation / distro is named
# in the boot loader (e.g. in the GRUB menu).
strings:
    productName:         ${dist_name} Linux
    shortProductName:    ${dist_name}
    version:             ${dist_release}
    shortVersion:        ${dist_release}
    versionedName:       ${dist_name} Linux ${dist_release}
    shortVersionedName:  ${dist_name} ${dist_release}
    bootloaderEntryName: ${dist_name}

# These images are loaded from the branding module directory.
#
# productIcon is used as the window icon, and will (usually) be used
#       by the window manager to represent the application. This image
#       should be square, and may be displayed by the window manager
#       as small as 16x16 (but possibly larger).
# productLogo is used as the logo at the top of the left-hand column
#       which shows the steps to be taken. The image should be square,
#       and is displayed at 80x80 pixels (also on HiDPI).
# productWelcome is shown on the welcome page of the application in
#       the middle of the window, below the welcome text. It can be
#       any size and proportion, and will be scaled to fit inside
#       the window. Use `welcomeExpandingLogo` to make it non-scaled.
#       Recommended size is 320x150.
images:
    productLogo:         "logo.png"
    productIcon:         "logo.png"
    productWelcome:      "languages.png"

# The slideshow is displayed during execution steps (e.g. when the
# installer is actually writing to disk and doing other slow things).
slideshow:               "show.qml"

# Colors for text and background components.
#
#  - sidebarBackground is the background of the sidebar
#  - sidebarText is the (foreground) text color
#  - sidebarTextHighlight sets the background of the selected (current) step.
#    Optional, and defaults to the application palette.
#  - sidebarSelect is the text color of the selected step.
#
style:
   sidebarBackground:    "${sidebackground}"
   sidebarText:          "${sidebartext}"
   sidebarTextSelect:    "${sidebartextselect}"
   sidebarTextHighlight: "${sidebartexthighlight}"
