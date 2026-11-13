# Koha notice editor plugin

Notice editor improvements for Koha 26.05 and 26.11, backported from Koha bugs
that are expected in Koha 27.05:

* [Bug 36588](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=36588):
  a Template Toolkit field picker. The field list offers the fields each notice
  actually receives, in Template Toolkit or in the bespoke `<< >>` syntax, and
  the Template Toolkit plugins with examples of their options.
* [Bug 39716](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=39716):
  notices are checked before saving. Errors that stop a notice from being
  generated (e.g. Template Toolkit syntax errors) prevent saving, warnings (e.g.
  an overdue notice that does not list the items) can be saved anyway.
* [Bug 43395](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=43395):
  the check also reports variables, fields and plugins the notice will not have.
* [Bug 38105](https://bugs.koha-community.org/bugzilla3/show_bug/cgi?id=38105)
  Parses the css and html properly. If HTML is not selected for the notice, it will print as it would print.
* [Bug 44117](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=44117):
  Adds a plugin hook to allow for inserting notice variables to the field picker in notices
  
The plugin does nothing on Koha versions that include these bugs.

## Installation

Download the `.kpz` file of the latest release and upload it in
Administration > Manage plugins. Plugins must be enabled in `koha-conf.xml`.

The plugin adds its JavaScript to the notice editor (Tools > Notices and
slips), and two API routes used by it, which need the `edit_notices`
permission:

* `GET /api/v1/contrib/noticeeditor/fields`
* `POST /api/v1/contrib/noticeeditor/validation`

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md).
