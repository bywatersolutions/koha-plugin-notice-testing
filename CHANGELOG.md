# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
