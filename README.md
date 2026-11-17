<h1>
<p align="center">
  <img src="./assets/logo.png" alt="Logo" width="128">
  <br>Larkdown.app
</h1>
  <p align="center">
	<strong>Your new default "open with" app for markdown files on macOS</strong>
    <br />
    <a href="#about">About</a>
    ·
    <a href="#download">Download</a>
    ·
    <a href="DEVELOPING.md">Developing</a>
    ·
    <a href="LICENSE.md">License</a>
  </p>
</p>

![screenshot](./assets/screenshot.png)

_Built as a universal native Swift app for macOS._

## About

Larkdown is a markdown editor that displays a rendered preview of the content in a side-by-side pane that updates as you type.

While there are other options available for viewing markdown files on macOS, they often come bundled within a larger piece of software. Larkdown is focused specifically on providing a fast, focused, stand-alone experience for quickly editing and viewing markdown files.

## Download

Larkdown can be downloaded as a `.dmg` from the [latest GitHub release](https://github.com/mikeokner/Larkdown/releases/latest).

1. Download the latest `.dmg` like "Larkdown-x.y.z.dmg" from the latest release
2. Open the `.dmg` file when the download is complete
3. In the window that opens, drag the "Larkdown" app to the "Applications" icon to install the app

You may then eject the "Larkdown" disk image and delete the `.dmg` file from your downloads

### Setting as default

To make Larkdown the default app for opening markdown files:

1. in a Finder window, right-click on a `.md` file and select "Get Info" from the options
2. in the info panel that opens, expand the "Open with" section and select "Larkdown.app" from the dropdown
3. click "Change All..." to make Larkdown the default for opening `.md` files

Once you've made Larkdown the default, you can also open files in Larkdown from the CLI using the `open` command like:

```console
$ open path/to/file.md
```

_Larkdown is free, open-source software with a publicly-verifiable build, signing, and release workflow in [GitHub Actions](https://github.com/mikeokner/Larkdown/actions/workflows/release.yml)._
