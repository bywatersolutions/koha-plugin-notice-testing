# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-11-13

### Added

- CONVERTED_TO_PRINT (Koha 26.11, the print notice of an email or SMS notice that could not be sent) is known: its fields are listed and its variables checked, borrower, branch and original_message

## [1.1.0] - 2026-11-13

### Changed

- Previews offer the records each notice receives instead of always a patron and an item: e.g. a basket and a vendor for ACQORDER, a vendor for claims, a patron, an item and a hold for hold notices, a suggestion, an ILL request, a booking... Notices not known get a patron and an item
- The records related to those given are used: the vendor and orders of a basket, the patron and item of a hold, the patron who made a suggestion...
- Notices sent once per item and combined into one message (CHECKOUT, CHECKIN, RENEWAL, HOLD, HOLDDGST) can be previewed with several items, or the patron's, combined as Koha does: lines of ---- separate the header and footer from what is repeated for each item
- OAI_HARVEST_REPORT is previewed with an OAI server, whose name, endpoint, set, data format and record type are shown instead of placeholders
- Notices that receive no patron (e.g. acquisition notices) are no longer previewed with an example patron
- The preview API takes `records` (by kind) instead of `patron` and `barcode`, and the fields API returns the `preview_records` of the notice

### Fixed

- Template checks: [% set _ "x" %] (a variable the notice receives followed by the _ operator) is no longer reported as a lowercase SET; arguments of macros and parameters of INCLUDE and PROCESS are variables; all the virtual methods Template Toolkit has for hashes (e.g. empty, first) are accepted; long templates are checked faster; processing errors use the includes of the language of the notice
- Previews: the latest related record is used, related to all the records given when possible (with a note otherwise); a hold on a record gets an item of that record; only the columns the database declares as relationships are followed (e.g. not the free text booksellerid of items)
- Notices that set a variable they receive to another kind of value (e.g. [% WHILE (item = overdues.next) %] in overdue notices) are no longer reported as errors, which prevented saving them
- Malformed descriptions from the notices_content_variables hook of a plugin no longer break the notice editor, and hook failures are logged
- Previews: <<table.column>> values are formatted as in sent notices (e.g. dates); HOLD notices are no longer combined (only HOLDDGST is); [% branch %] is the library the notice is sent with (the pickup library of holds, the circulation control library of checkouts); Enter in the preview fields previews instead of saving the notice
- A variable the notice receives with the name of a directive (the [% set %] of OAI_HARVEST_REPORT) is no longer reported as a lowercase directive
- Templates without "HTML message" ticked are previewed as text, tags included, as they are sent and printed, instead of being rendered as HTML
- Previews of combined notices have the subject of the first item, as Koha keeps the subject of the first notice queued
- Previews are shown in a sandboxed frame, as Koha shows the notices of patrons (bug 33260): nothing in a notice can run, the *NoticeStylesheet stylesheets are loaded and CSS on body applies
- Only the latest preview is shown: a slower earlier one no longer replaces it
- While the templates are checked before saving, the Save button shows "Saving..." and the notice cannot be saved twice
- The problems and line numbers of a template are cleared when it is emptied; the line numbers follow edits without slowing typing in long templates
- The list of fields and the message body share the width of their template, so that they stay within it whatever the width of the screen: the list takes about a third of it (long names are shown in full on hover), the message body the rest instead of a fixed 80 columns, and the "Insert as:" choices wrap
- "and N more" is translated with plural forms, "or" without its spaces, and the "Insert as:" radio buttons are labelled as a group for screen readers

## [1.0.0] - 2026-11-10

### Added

- A filter above the list of fields shows the fields matching what is typed, with their group heading, or the whole group when its heading matches
- Plugins can describe the content they add to notices with the notices_content_variables hook (Koha bug pending): the field picker offers it under plugin_content.<namespace>, only in the notices they add content to, and templates using it are checked
- Previews pass the records as tables too, with the module, code and transport of the notice, as the code sending each notice does, so plugins adding content to notices (e.g. Rapido ILL for holds on ILL requests) show it in previews
- The field picker offers the content Koha plugins add to notices with the notices_content hook, as plugin_content.<namespace>, and a namespace no enabled plugin adds is reported as a warning
- The field picker lists the keys of hashes whose keys are known: e.g. for SR_SLIP, branch.name and a loop on branch.items with item.title...; for the due digests, the checkout fields in the checkouts loop
- Keys that such hashes do not have (e.g. branch.nmae) are reported as warnings, as they print nothing
- Preview any notice, not only the few Koha can preview, with the data of a patron and an item chosen by card number and barcode; data the patron doesn't have is replaced by example records or placeholders, and listed above the preview
- HTML notices are previewed as HTML with the notice CSS, sanitized by DOMPurify

### Fixed

- Template Toolkit directives not written in capitals (e.g. [% else %], [% foreach %]) are reported: as an error when the template cannot be parsed, else as a warning, as the word is then read as a variable
- A notice that is listed (e.g. SR_SLIP) no longer accepts the variables of the overdue notices (overdues, bib, count...): only codes chosen by the library in the overdue notice triggers do
- [% FOREACH list %] without a loop variable no longer reports an unknown variable 'import', and variables in it are not checked unless the list holds objects
- A loop without a loop variable no longer gives the type of its list to the variable of the next loop
- "Subroutine ... redefined" warnings when installing the plugin: its modules moved from `lib/NoticeEditor/` into the plugin namespace, so Koha no longer loads them twice

## [0.1.2] - 2026-11-06

### Added

- More Template Toolkit plugins in the field picker: AdditionalContents, CirculationRules (including renewals), Desks, Registers, Remove_MARC_punctuation, the logged in library from Branches, Koha.MultivaluePreference and KohaDates.tz (#5)

### Changed

- The plugins of the field picker are in alphabetical order (#5)

## [0.1.1] - 2026-11-06

## [0.1.0] - 2026-11-06

### Added

- Template Toolkit field picker (Koha bug 36588)
- Check notices before saving them (Koha bugs 39716 and 43395)
