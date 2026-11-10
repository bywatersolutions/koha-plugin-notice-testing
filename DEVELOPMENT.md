# Koha notice editor plugin - Development guide

## Relationship with Koha

The plugin backports Koha bugs 36588, 39716, 43395, 38105 and 29490. Its code is kept as
close as possible to the code of those bugs, so that changes made to one can be
copied to the other until the bugs are in a Koha release:

| Plugin | Koha |
| --- | --- |
| `Variables.pm` | `Koha/Notice/Template/Variables.pm` |
| `Validator.pm` | `Koha/Notice/Template/Validator.pm` |
| `Preview.pm` | `Koha/Notice/Template/Preview.pm` |
| `TableConfig.pm` | `C4::Letters::tt_table_config` |
| `Checks.pm` | `Koha::Notice::Template::repeatable_content`, `validate` |
| `Fields.pm` | the field list of `tools/letter.pl` |
| `Controller.pm` | `Koha/REST/V1/NoticeTemplates.pm`; `preview` is `svc/letters/preview` |
| `js/notice-editor.js` | `koha-tmpl/intranet-tmpl/prog/js/letter.js` |
| `css/notice-editor.css` | the styles of `koha-tmpl/intranet-tmpl/prog/en/modules/tools/letter.tt` |

`Variables.pm` lists the data each notice receives. When Koha adds or
changes a notice, update it: `t/db_dependent/NoticeEditor/SampleNotices.t`
fails when a sample notice of the Koha version tested is not listed.

The JavaScript extends the notice editor page of Koha: it relies on its markup
(`#add_notice`, `fieldset.mtt`, `select[name="SQLfieldname"]`, `.insert`...).
Test the plugin on each supported Koha version.

## Testing

Launch KTD with the plugin, for each supported Koha version:

```bash
KOHA_IMAGE=26.05 SYNC_REPO=/path/to/koha ktd --single-plugin /path/to/koha-plugin-notice-testing --name ne2605 up -d
ktd --name ne2605 --shell --run "cd /kohadevbox/koha && perl misc/devel/install_plugins.pl"
```

Then run the tests:

```bash
ktd --name ne2605 --shell --run "cd /kohadevbox/plugins/koha-plugin-notice-testing && export PERL5LIB=\$PERL5LIB:. && prove -r t/"
```

Format the code with Koha's `misc/devel/tidy.pl` before committing.

## Releasing

`npm version patch|minor|major` updates the version in the plugin and
CHANGELOG.md. Pushing the tag builds the `.kpz` and the GitHub release.
