/* Koha notice editor plugin: backport of Koha bugs 36588, 39716 and 43395 to the
 * notice editor of Koha 26.05 and 26.11 (tools/letter.pl).
 *
 * The functions before the initialisation are copies of those of
 * koha-tmpl/intranet-tmpl/prog/js/letter.js in those bugs: keep them in sync.
 */
(function () {
  var API = "/api/v1/contrib/noticeeditor";

  function templateFieldset(mtt, lang) {
    return $("#content_" + mtt + "_" + lang).closest("fieldset.mtt");
  }

  /*
   * The nodes of a translated message: each %s in text is replaced by the next
   * value. Strings are shown in bold, jQuery objects are inserted as they are.
   */
  function messageNodes(text, values) {
    var nodes = [];
    text.split("%s").forEach(function (part, i, parts) {
      if (part) {
        nodes.push(document.createTextNode(part));
      }
      if (i < parts.length - 1 && i < values.length) {
        var value = values[i];
        nodes.push(
          typeof value === "string"
            ? $("<strong></strong>").text(value)[0]
            : value[0],
        );
      }
    });
    return nodes;
  }

  // A list of values, in bold, collapsed after the first 5
  function collapsibleList(values) {
    var shown = 5;
    var list = $("<span></span>");
    var add = function (target, value, index) {
      if (index > 0) {
        target.append(document.createTextNode(", "));
      }
      target.append($("<strong></strong>").text(value));
    };
    values.slice(0, shown).forEach(function (value, index) {
      add(list, value, index);
    });
    if (values.length > shown) {
      var more = $('<span class="more_variables" hidden></span>');
      values.slice(shown).forEach(function (value, index) {
        add(more, value, shown + index);
      });
      var toggle = $('<span class="show_more"> <a href="#"></a></span>');
      toggle
        .find("a")
        .text(
          __nx("and {count} more", "and {count} more", values.length - shown, {
            count: values.length - shown,
          }),
        )
        .on("click", function (e) {
          e.preventDefault();
          more.prop("hidden", false);
          toggle.remove();
        });
      list.append(more, toggle);
    }
    return list;
  }

  function describeTemplateProblem(problem) {
    if (problem.type === "tt_syntax") {
      return messageNodes(
        __(
          "Template Toolkit syntax error: %s. The notice cannot be generated until it is fixed.",
        ),
        [problem.error],
      );
    }
    if (problem.type === "unclosed_tag") {
      return messageNodes(
        __("%s has no matching %s, so it will be printed as text."),
        ["[%", "%]"],
      );
    }
    if (problem.type === "lowercase_directive") {
      return messageNodes(
        problem.severity === "error"
          ? __(
              "Template Toolkit directives must be in capitals: write %s instead of %s. The notice cannot be generated until it is fixed.",
            )
          : __(
              "Template Toolkit directives must be in capitals: write %s instead of %s. As written, it is read as a variable, so the notice will not show what is expected.",
            ),
        [problem.directive, problem.used],
      );
    }
    if (problem.type === "tt_error") {
      return messageNodes(
        __("Template Toolkit error: %s. The notice cannot be generated."),
        [problem.error],
      );
    }
    if (problem.type === "missing_repeatable_content") {
      var markers = ["[% FOREACH ... IN " + problem.loop + " %] ... [% END %]"];
      (problem.tokens || []).forEach(function (token) {
        markers.push("<<" + token + ">>");
      });
      (problem.tags || []).forEach(function (tag) {
        markers.push("<" + tag + ">...</" + tag + ">");
      });
      var choices = $("<span></span>");
      markers.forEach(function (marker, index) {
        if (index > 0) {
          choices.append(document.createTextNode(" " + __("or") + " "));
        }
        choices.append($("<code></code>").text(marker));
      });
      return messageNodes(
        __(
          "This notice is sent with a list of items, but the message body has nothing to list them with, so the items will not be in the notice. Add %s.",
        ),
        [choices],
      );
    }
    if (problem.type === "unknown_variable") {
      // Used as a filter, it is an error: the notice cannot be generated
      var nodes = messageNodes(
        problem.severity === "error"
          ? __(
              "%s is used as a filter but is not available to this notice, so the notice cannot be generated.",
            )
          : __("%s is not available to this notice, so it will print nothing."),
        [problem.variable],
      );
      if (problem.suggestion) {
        nodes = nodes.concat(
          messageNodes(" " + __("Did you mean %s?"), [problem.suggestion]),
        );
      } else if (problem.available && problem.available.length) {
        nodes = nodes.concat(
          messageNodes(" " + __("This notice receives: %s."), [
            collapsibleList(problem.available),
          ]),
        );
      }
      return nodes;
    }
    if (problem.type === "unknown_method") {
      var path = problem.variable.split(".");
      return messageNodes(
        __(
          "%s does not exist: %s has no field or method named %s, so the notice cannot be generated.",
        ),
        [problem.variable, problem.class, path[path.length - 1]],
      );
    }
    if (
      problem.type === "unknown_key" &&
      /^plugin_content\.[^.]+$/.test(problem.variable)
    ) {
      var pluginNodes = messageNodes(
        __(
          "No enabled plugin adds content to this notice as %s, so it will print nothing.",
        ),
        [problem.variable],
      );
      if (problem.keys && problem.keys.length) {
        pluginNodes = pluginNodes.concat(
          messageNodes(" " + __("Plugins add to it: %s."), [
            collapsibleList(
              problem.keys.map(function (namespace) {
                return "plugin_content." + namespace;
              }),
            ),
          ]),
        );
      }
      return pluginNodes;
    }
    if (problem.type === "unknown_key") {
      var keyPath = problem.variable.split(".");
      var key = keyPath.pop();
      return messageNodes(
        __("%s has no key %s, so it will print nothing. Its keys are: %s."),
        [keyPath.join("."), key, collapsibleList(problem.keys || [])],
      );
    }
    if (problem.type === "missing_plugin") {
      return messageNodes(
        problem.severity === "error"
          ? __(
              "The %s plugin is used as a filter without being loaded, so the notice cannot be generated. Add %s at the top.",
            )
          : __(
              "The %s plugin is used without being loaded, so it will print nothing. Add %s at the top.",
            ),
        [problem.plugin, "[% USE " + problem.plugin + " %]"],
      );
    }
    if (problem.type === "unknown_block") {
      return messageNodes(
        __(
          "The block %s is processed, but the template does not define it, so the notice cannot be generated.",
        ),
        [problem.block],
      );
    }
    return [document.createTextNode(problem.type)];
  }

  // Where the problem is: in the subject, or on which lines of the body
  function problemLocation(problem, fieldset) {
    var location = $('<span class="problem_location"></span>');
    if (problem.field === "title") {
      return location.text(" — " + __("in the message subject"));
    }
    var lines = problem.lines || [];
    if (!lines.length) {
      return null;
    }
    location.append(
      document.createTextNode(
        " — " + __n("on line", "on lines", lines.length) + " ",
      ),
    );
    lines.forEach(function (line, index) {
      if (index > 0) {
        location.append(document.createTextNode(", "));
      }
      var link = $('<a href="#" class="go_to_line"></a>').text(line);
      link.on("click", function (e) {
        e.preventDefault();
        $("#template_problems_modal").modal("hide");
        goToLine(fieldset, line);
      });
      location.append(link);
    });
    return location;
  }

  // The lists of errors and warnings of a template, with short headings in the modal
  function problemAlerts(problems, fieldset, in_modal) {
    var alerts = $("<div></div>");
    [
      {
        severity: "error",
        css: "alert-danger",
        heading: in_modal
          ? __("Errors:")
          : __("This template cannot be saved until these errors are fixed:"),
      },
      {
        severity: "warning",
        css: "alert-warning",
        heading: __("Warnings:"),
      },
    ].forEach(function (group) {
      var found = problems.filter(function (problem) {
        return (problem.severity || "warning") === group.severity;
      });
      if (!found.length) {
        return;
      }
      var list = $("<ul></ul>");
      found.forEach(function (problem) {
        list.append(
          $("<li></li>")
            .append(describeTemplateProblem(problem))
            .append(problemLocation(problem, fieldset)),
        );
      });
      alerts.append(
        $('<div class="alert"></div>')
          .addClass(group.css)
          .append($("<strong></strong>").text(group.heading), list),
      );
    });
    return alerts;
  }

  function showTemplateProblems(fieldset, problems) {
    // The error of a saved template is already shown at the top of it
    if (fieldset.find(".template_toolkit_error").length) {
      problems = problems.filter(function (problem) {
        return problem.type !== "tt_error";
      });
    }
    var container = fieldset.find(".template_problems");
    container.empty();
    if (problems.length) {
      container.append(problemAlerts(problems, fieldset));
    }
    updateLineGutter(fieldset, problems);
  }

  /*
   * Line numbers next to the message body, shown when problems are on given
   * lines of it. Lines are measured in a hidden copy of the textarea, as long
   * lines wrap on several rows.
   */
  // Wrap a message body with a line gutter, once
  function ensureLineGutter(fieldset) {
    var textarea = fieldset.find('textarea[name="content"]');
    var gutter = fieldset.find(".line_gutter");
    if (gutter.length || !textarea.length) {
      return gutter;
    }
    textarea.wrap('<div class="content_with_gutter"></div>');
    gutter = $('<div class="line_gutter" aria-hidden="true"></div>');
    textarea.before(gutter);
    // Measuring the lines is slow on long templates: wait for a pause in
    // typing or resizing
    var render = function () {
      clearTimeout(gutter.data("timer"));
      gutter.data(
        "timer",
        setTimeout(function () {
          renderLineGutter(textarea, gutter);
        }, 150),
      );
    };
    textarea.on("input.line_gutter", render).on("scroll.line_gutter", function () {
      gutter.scrollTop(textarea.scrollTop());
    });
    if (window.ResizeObserver) {
      new ResizeObserver(render).observe(textarea[0]);
    }
    renderLineGutter(textarea, gutter);
    return gutter;
  }

  function updateLineGutter(fieldset, problems) {
    var marks = {};
    problems.forEach(function (problem) {
      if (problem.field !== "content") return;
      (problem.lines || []).forEach(function (line) {
        if (marks[line] !== "error") {
          marks[line] = problem.severity || "warning";
        }
      });
    });
    var gutter = ensureLineGutter(fieldset);
    gutter.data("marks", marks); // an empty object clears old highlights
    renderLineGutter(fieldset.find('textarea[name="content"]'), gutter);
  }

  function lineHeights(textarea) {
    var style = window.getComputedStyle(textarea[0]);
    var mirror = $('<div aria-hidden="true"></div>').css({
      position: "absolute",
      visibility: "hidden",
      top: 0,
      left: "-9999px",
      width:
        textarea[0].clientWidth -
        parseFloat(style.paddingLeft) -
        parseFloat(style.paddingRight) +
        "px",
      "white-space": "pre-wrap",
      "overflow-wrap": "break-word",
      "font-family": style.fontFamily,
      "font-size": style.fontSize,
      "font-weight": style.fontWeight,
      "letter-spacing": style.letterSpacing,
      "line-height": style.lineHeight,
      "tab-size": style.tabSize,
    });
    textarea
      .val()
      .split("\n")
      .forEach(function (line) {
        mirror.append($("<div></div>").text(line || " "));
      });
    $("body").append(mirror);
    var heights = mirror
      .children()
      .map(function () {
        return this.getBoundingClientRect().height;
      })
      .get();
    mirror.remove();
    return heights;
  }

  function renderLineGutter(textarea, gutter) {
    if (!textarea.is(":visible")) {
      return;
    }
    var marks = gutter.data("marks") || {};
    var style = window.getComputedStyle(textarea[0]);
    gutter.empty().css({
      height: textarea.outerHeight() + "px",
      "padding-top": style.paddingTop,
      "padding-bottom": style.paddingBottom,
      "font-family": style.fontFamily,
      "font-size": style.fontSize,
      "line-height": style.lineHeight,
    });
    lineHeights(textarea).forEach(function (height, index) {
      var line = $("<div></div>")
        .text(index + 1)
        .css("height", height + "px");
      if (marks[index + 1]) {
        line.addClass("line_" + marks[index + 1]);
      }
      gutter.append(line);
    });
    gutter.scrollTop(textarea.scrollTop());
  }

  // Select a line of the message body, opening its template if needed
  function goToLine(fieldset, line) {
    var panel = fieldset.closest(".panel-collapse");
    var go = function () {
      var textarea = fieldset.find('textarea[name="content"]');
      var lines = textarea.val().split("\n");
      if (line > lines.length) {
        return;
      }
      var start = 0;
      for (var i = 0; i < line - 1; i++) {
        start += lines[i].length + 1;
      }
      textarea.focus();
      textarea[0].setSelectionRange(start, start + lines[line - 1].length);
      var offset = lineHeights(textarea)
        .slice(0, line - 1)
        .reduce(function (sum, height) {
          return sum + height;
        }, 0);
      textarea.scrollTop(Math.max(0, offset - textarea.innerHeight() / 3));
      renderLineGutter(textarea, fieldset.find(".line_gutter"));
    };
    if (panel.length && !panel.hasClass("show")) {
      panel.one("shown.bs.collapse", go).collapse("show");
    } else {
      go();
    }
  }

  // The name of a template, as shown in its heading, and its language if any
  function templateName(mtt, lang) {
    var name = $("#" + mtt + "_" + lang + "_heading .panel-title")
      .text()
      .trim();
    var language = $("#lang_" + lang + "-tab")
      .text()
      .trim();
    return language ? name + " (" + language + ")" : name || mtt;
  }

  /*
   * Show on the Save button that the notice is being saved (its templates are
   * checked first), as other saves do with KOHA.AJAX.MarkRunning, or that it
   * is not anymore. ajax.js is not loaded on this page in every version: its
   * markup is used then.
   */
  var saving = false;
  var saving_redirect;
  function markSaving(running) {
    var button = $("#submit_form");
    saving = running;
    if (running) {
      saving_redirect = $("#redirect").val();
      button.data("original-html", button.html());
      if (window.KOHA && KOHA.AJAX) {
        KOHA.AJAX.MarkRunning(button, __("Saving..."));
      } else {
        button
          .prop("disabled", true)
          .text(__("Saving..."))
          .prepend('<span class="loading"></span>');
      }
    } else {
      if (window.KOHA && KOHA.AJAX) {
        KOHA.AJAX.MarkDone(button);
      }
      button.prop("disabled", false).html(button.data("original-html"));
    }
  }

  /*
   * Before saving: list the problems of the templates in a modal. Saving is
   * only possible when there are warnings but no errors.
   */
  function confirmTemplateProblems(with_problems, save) {
    var modal = $("#template_problems_modal");
    var has_errors = with_problems.some(function (template) {
      return template.problems.some(function (problem) {
        return problem.severity === "error";
      });
    });
    modal
      .find(".modal-title")
      .text(
        has_errors
          ? __("This notice cannot be saved")
          : __("Save this notice with warnings?"),
      );
    var body = modal.find(".modal-body").empty();
    if (has_errors) {
      body.append(
        $("<p></p>").text(
          __(
            "Some templates have errors that would stop the notice from being generated. Fix them, then save again.",
          ),
        ),
      );
    }
    with_problems.forEach(function (template) {
      body.append(
        $("<h2></h2>").text(templateName(template.mtt, template.lang)),
        problemAlerts(
          template.problems,
          templateFieldset(template.mtt, template.lang),
          true,
        ),
      );
    });
    modal
      .find(".save_anyway")
      .toggle(!has_errors)
      .off("click")
      .on("click", function () {
        modal.modal("hide");
        save();
      });
    modal
      .off("hidden.bs.modal.problems")
      .on("hidden.bs.modal.problems", function () {
        // Open the templates with problems so they can be fixed
        with_problems.forEach(function (template) {
          templateFieldset(template.mtt, template.lang)
            .closest(".panel-collapse")
            .collapse("show");
        });
      });
    modal.modal("show");
  }

  /*
   * Check the given fieldset.mtt templates (default: all of them) on the
   * server. Problems are shown in each template; the returned promise
   * resolves with a list of { mtt, lang, problems } for templates with problems.
   */
  function validateTemplates(fieldsets) {
    fieldsets = fieldsets || $("fieldset.mtt");
    var templates = fieldsets
      .map(function () {
        return {
          message_transport_type: $(this)
            .find('input[name="message_transport_type"]')
            .val(),
          lang: $(this).find('input[name="lang"]').val(),
          title: $(this).find('input[name="title"]').val(),
          content: $(this).find('textarea[name="content"]').val(),
        };
      })
      .get();

    return $.ajax({
      url: API + "/validation",
      type: "POST",
      contentType: "application/json",
      data: JSON.stringify({
        module: $("#add_notice select[name='module']").val(),
        code: $("#code").val(),
        templates: templates,
      }),
      dataType: "json",
    }).then(function (response) {
      var with_problems = [];
      var checked = {};
      response.templates.forEach(function (template) {
        checked[template.message_transport_type + "_" + template.lang] = 1;
        showTemplateProblems(
          templateFieldset(template.message_transport_type, template.lang),
          template.problems,
        );
        if (template.problems.length) {
          with_problems.push({
            mtt: template.message_transport_type,
            lang: template.lang,
            problems: template.problems,
          });
        }
      });
      // Templates left empty are not checked: clear what was shown for them
      fieldsets.each(function () {
        var key =
          $(this).find('input[name="message_transport_type"]').val() +
          "_" +
          $(this).find('input[name="lang"]').val();
        if (!checked[key]) {
          showTemplateProblems($(this), []);
        }
      });
      return with_problems;
    });
  }

  // "tt", "bespoke", or "mixed" (Template Toolkit, bespoke where needed)
  function insertSyntax(fieldset) {
    return (
      fieldset.find(".insert_syntax input[type='radio']:checked").val() || "tt"
    );
  }

  function bespokeText(option) {
    if (option.data("bespoke")) {
      return option.data("bespoke");
    }
    return option.val() ? "<<" + option.val() + ">>" : "";
  }

  function textToInsert(option, syntax) {
    if (syntax === "tt") {
      return option.data("tt") || "";
    }
    if (syntax === "mixed") {
      return option.data("tt") || bespokeText(option);
    }
    return bespokeText(option);
  }

  // Group headings of the list of fields, e.g. ---borrower---
  function isFieldHeading(option) {
    return /^-{3}.*-{3}$/.test(option.text().trim());
  }

  /*
   * Show the fields that can be inserted with the chosen syntax and that match
   * the filter, if any: a group heading is shown when it or any of its fields
   * matches, and all its fields when it matches (e.g. "borrower")
   */
  function updateInsertableFields(fieldset) {
    var syntax = insertSyntax(fieldset);
    var filter = (fieldset.find(".field_filter").val() || "")
      .trim()
      .toLowerCase();
    var groups = [];
    fieldset.find('select[name="SQLfieldname"] option').each(function () {
      var option = $(this);
      var option_syntax = option.data("syntax") || "both";
      var entry = {
        option: option,
        syntax_shown:
          option_syntax === "both" ||
          option_syntax === syntax ||
          // Mixed: the Template Toolkit fields, and the bespoke ones it cannot replace
          (syntax === "mixed" &&
            (option_syntax === "tt" || option.data("fallback"))),
        matches:
          filter === "" || option.text().toLowerCase().indexOf(filter) !== -1,
      };
      if (isFieldHeading(option) || !groups.length) {
        groups.push({
          heading: isFieldHeading(option) ? entry : null,
          fields: [],
        });
      }
      if (!isFieldHeading(option)) {
        groups[groups.length - 1].fields.push(entry);
      }
    });

    var show = function (entry, shown) {
      var insertable = shown && textToInsert(entry.option, syntax) !== "";
      entry.option.prop("hidden", !shown).prop("disabled", !insertable);
      if (!insertable) {
        entry.option.prop("selected", false);
      }
    };
    groups.forEach(function (group) {
      var heading_matches =
        group.heading && filter !== "" && group.heading.matches;
      var any_field = false;
      group.fields.forEach(function (field) {
        var shown = field.syntax_shown && (heading_matches || field.matches);
        any_field = any_field || shown;
        show(field, shown);
      });
      if (group.heading) {
        show(
          group.heading,
          group.heading.syntax_shown &&
            (filter === "" || heading_matches || any_field),
        );
      }
    });
  }

  // The filter of the list of fields
  function fieldFilter(mtt, lang, disabled) {
    var id = "field_filter_" + mtt + "_" + lang;
    return $("<div></div>").append(
      $('<label class="visually-hidden"></label>')
        .attr("for", id)
        .text(__("Filter the fields:")),
      $('<input type="search" class="field_filter" autocomplete="off" />')
        .attr({ id: id, placeholder: __("Filter fields") })
        .prop("disabled", disabled),
    );
  }

  // The fields of a field option, for the notice editor of Koha bug 36588
  function fieldOption(field) {
    var option = $("<option></option>")
      .val(field.value || "")
      .text(field.text)
      .attr("title", field.text)
      .attr("data-syntax", field.syntax);
    if (field.tt) {
      option.attr("data-tt", field.tt);
    }
    if (field.bespoke) {
      option.attr("data-bespoke", field.bespoke);
    }
    if (field.use) {
      option.attr("data-use", field.use);
    }
    if (field.fallback) {
      option.attr("data-fallback", "1");
    }
    return option;
  }

  // The choice of the syntax to insert fields with, and its hint
  function insertSyntaxChoice(name, syntaxes, only_bespoke, disabled) {
    var labels = {
      tt: __("Template Toolkit [% %]"),
      mixed: __("Template Toolkit, bespoke where needed"),
      bespoke: __("Bespoke << >>"),
    };
    var label_id = "insert_syntax_label_" + name;
    var choice = $(
      '<div class="insert_syntax" role="radiogroup"></div>',
    )
      .attr("aria-labelledby", label_id)
      .append($("<span></span>").attr("id", label_id).text(__("Insert as:")));
    ["tt", "mixed", "bespoke"].forEach(function (syntax) {
      if (syntaxes.indexOf(syntax) === -1) {
        return;
      }
      var input = $('<input type="radio" />')
        .addClass("insert_syntax_" + syntax)
        .attr("name", name)
        .val(syntax)
        .prop("disabled", disabled);
      choice.append(
        $('<label class="radio-inline"></label>').append(
          input,
          document.createTextNode(" " + labels[syntax]),
        ),
      );
    });
    var hint;
    if (syntaxes.indexOf("mixed") !== -1) {
      hint = __(
        "Template Toolkit cannot use some data of this notice yet (%s): those fields are inserted as << >>.",
      ).format(only_bespoke.join(", "));
    } else if (syntaxes.indexOf("bespoke") === -1) {
      hint = __(
        "This notice does not receive any data the bespoke << >> syntax can use.",
      );
    } else if (syntaxes.indexOf("tt") === -1) {
      hint = __(
        "This notice does not receive any data Template Toolkit can use.",
      );
    }
    if (hint) {
      choice.append($('<div class="hint"></div>').text(hint));
    }
    return choice;
  }

  function insertFields(fieldset) {
    var myQuery = fieldset.find('textarea[name="content"]');
    var syntax = insertSyntax(fieldset);
    var plugins = [];

    fieldset
      .find('select[name="SQLfieldname"] option:selected')
      .each(function () {
        var text = textToInsert($(this), syntax);
        if (text) {
          myQuery.insertAtCaret(text);
          if (syntax !== "bespoke" && $(this).data("use")) {
            plugins.push($(this).data("use"));
          }
        }
      });

    // Load the plugins used by the inserted examples, if not loaded yet
    var content = myQuery.val();
    var missing = plugins.filter(function (plugin, index) {
      var use = new RegExp("\\[%-?\\s*USE\\s+" + plugin + "\\b");
      return plugins.indexOf(plugin) === index && !use.test(content);
    });
    if (missing.length) {
      myQuery.val(
        missing
          .map(function (plugin) {
            return "[% USE " + plugin + " %]\n";
          })
          .join("") + content,
      );
    }
  }

  var MODAL =
    '<div class="modal" id="template_problems_modal" tabindex="-1" aria-labelledby="template_problems_modal_label" aria-hidden="true">' +
    '<div class="modal-dialog modal-lg"><div class="modal-content">' +
    '<div class="modal-header"><h1 class="modal-title" id="template_problems_modal_label"></h1>' +
    '<button type="button" class="btn-close" data-bs-dismiss="modal"></button></div>' +
    '<div class="modal-body"></div>' +
    '<div class="modal-footer"><button type="button" class="btn btn-primary save_anyway"></button>' +
    '<button type="button" class="btn btn-default deny cancel" data-bs-dismiss="modal"><i class="fa fa-times"></i> <span class="go_back"></span></button>' +
    "</div></div></div></div>";

  $(document).ready(function () {
    var form = $("#add_notice");
    var fieldsets = $("fieldset.mtt");
    if (!form.length || !fieldsets.length) {
      return;
    }

    // The message body takes the width left by the list of fields (see the
    // CSS), as in Koha with bug 36588
    fieldsets
      .find('textarea[name="content"]')
      .closest("table")
      .addClass("message_body_editor");

    // Template Toolkit errors of saved templates: remove the file and line of tools/letter.pl
    $(".template_toolkit_error").each(function () {
      $(this)
        .contents()
        .filter(function () {
          return this.nodeType === 3;
        })
        .each(function () {
          this.nodeValue = this.nodeValue.replace(
            / at \S+\/tools\/letter\.pl line \d+\.\s*$/,
            "",
          );
        });
    });

    $("body").append(MODAL);
    $("#template_problems_modal .save_anyway").text(__("Save anyway"));
    $("#template_problems_modal .go_back").text(__("Go back to editing"));

    // Problems and "Check template" in each template
    fieldsets.each(function () {
      var fieldset = $(this);
      var mtt = fieldset.find('input[name="message_transport_type"]').val();
      var lang = fieldset.find('input[name="lang"]').val();
      var readonly = fieldset
        .find('select[name="SQLfieldname"]')
        .is(":disabled");
      var check = $(
        '<button type="button" class="btn btn-default btn-xs check_template"><i class="fa-solid fa-spell-check"></i> </button>',
      )
        .attr({ "data-mtt": mtt, "data-lang": lang })
        .prop("disabled", readonly)
        .append(document.createTextNode(__("Check template")));
      fieldset
        .children("ol")
        .append(
          $("<li></li>").append(
            '<div class="template_problems" aria-live="polite"></div>',
            check,
          ),
        );
    });

    // The fields of the notice, and the syntaxes it can use
    var module = form.find("select[name='module']").val();
    $.getJSON(API + "/fields", {
      module: module,
      code: $("#code").val(),
    }).then(function (response) {
      showPreviewRecords(response.preview_records, response.preview_combines);
      fieldsets.each(function () {
        var fieldset = $(this);
        var select = fieldset.find('select[name="SQLfieldname"]');
        var mtt = fieldset.find('input[name="message_transport_type"]').val();
        var lang = fieldset.find('input[name="lang"]').val();
        select.empty().append(response.fields.map(fieldOption));
        if (!fieldset.find(".field_filter").length) {
          select.before(fieldFilter(mtt, lang, select.is(":disabled")));
        }
        select.after(
          insertSyntaxChoice(
            "insert_syntax_" + mtt + "_" + lang,
            response.insert_syntaxes,
            response.only_bespoke,
            select.is(":disabled"),
          ),
        );

        // Default to the syntax the template already uses (TT otherwise)
        var content = fieldset.find('textarea[name="content"]').val() || "";
        var bespoke =
          content.indexOf("<<") !== -1 && content.indexOf("[%") === -1;
        var preferred = bespoke
          ? fieldset.find(".insert_syntax_bespoke")
          : fieldset.find(".insert_syntax_tt, .insert_syntax_mixed").first();
        if (!preferred.length) {
          preferred = fieldset
            .find(".insert_syntax input[type='radio']")
            .first();
        }
        preferred.prop("checked", true);
        updateInsertableFields(fieldset);
      });
    });

    $(document).on("change", ".insert_syntax input[type='radio']", function () {
      updateInsertableFields($(this).closest("fieldset.mtt"));
    });

    // Filter the list of fields as you type; Escape clears the filter, and
    // Enter does not submit the notice
    $(document)
      .on("input search", ".field_filter", function () {
        updateInsertableFields($(this).closest("fieldset.mtt"));
      })
      .on("keydown", ".field_filter", function (e) {
        if (e.key === "Enter") {
          e.preventDefault();
        } else if (e.key === "Escape" && $(this).val() !== "") {
          e.preventDefault();
          $(this).val("");
          updateInsertableFields($(this).closest("fieldset.mtt"));
        }
      });

    // Replace the insertion of core, which only knows the bespoke syntax
    $(".insert")
      .off("click")
      .on("click", function () {
        insertFields(
          $("#" + $(this).data("containerid") + "_panel").find("fieldset.mtt"),
        );
      });

    $(document).on("click", ".check_template", function (e) {
      e.preventDefault();
      var button = $(this);
      var fieldset = templateFieldset(button.data("mtt"), button.data("lang"));
      var title = fieldset.find('input[name="title"]').val();
      var content = fieldset.find('textarea[name="content"]').val();
      if (!title && !content) {
        showTemplateProblems(fieldset, []);
        return;
      }
      button.prop("disabled", true);
      validateTemplates(fieldset)
        .then(
          function (with_problems) {
            if (!with_problems.length) {
              fieldset
                .find(".template_problems")
                .html(
                  $('<div class="alert alert-success"></div>').text(
                    __("No problems found."),
                  ),
                );
            }
          },
          function () {
            fieldset
              .find(".template_problems")
              .html(
                $('<div class="alert alert-danger"></div>').text(
                  __("The template could not be checked."),
                ),
              );
          },
        )
        .always(function () {
          button.prop("disabled", false);
        });
    });

    // Check the templates before the checks of core, and saving. While they
    // are checked, the Save button shows that the notice is being saved, and
    // it is not saved twice
    var validator = form.data("validator");
    if (validator) {
      var core_submit = validator.settings.submitHandler;
      var submit = function (form_element) {
        if (core_submit.call(validator, form_element) === false) {
          // Core did not save it (e.g. a missing subject)
          markSaving(false);
        }
      };
      validator.settings.submitHandler = function (form_element) {
        if (saving) {
          return false;
        }
        markSaving(true);
        validateTemplates().then(
          function (with_problems) {
            if (!with_problems.length) {
              return submit(form_element);
            }
            markSaving(false);
            confirmTemplateProblems(with_problems, function () {
              markSaving(true);
              submit(form_element);
            });
          },
          function () {
            // Do not block saving if the check itself failed
            submit(form_element);
          },
        );
        return false;
      };
      // "Save and continue editing" while saving must not change where the
      // notice being saved goes (core sets it before this runs)
      $("#saveandcontinue").on("click", function () {
        if (saving) {
          $("#redirect").val(saving_redirect);
        }
      });
    }

    // Explain the problems of the saved templates when opening a notice
    if ($("#code").val() && $("#code").attr("type") === "hidden") {
      validateTemplates();
    }
  });

  // Previews (Koha bugs 38105 and 29490)

  // The kinds of records notices can be previewed with: their name, and what
  // to enter to find them
  var PREVIEW_RECORDS = {
    patron: [__("Patron"), __("Card number")],
    item: [__("Item"), __("Barcode")],
    basket: [__("Basket"), __("Basket number")],
    order: [__("Order"), __("Order number")],
    vendor: [__("Vendor"), __("Vendor ID or name")],
    hold: [__("Hold"), __("Hold ID")],
    suggestion: [__("Suggestion"), __("Suggestion number")],
    illrequest: [__("ILL request"), __("Request ID")],
    booking: [__("Booking"), __("Booking ID")],
    article_request: [__("Article request"), __("Request ID")],
    recall: [__("Recall"), __("Recall ID")],
    ticket: [__("Catalog concern"), __("Concern ID")],
    subscription: [__("Subscription"), __("Subscription number")],
    oai_server: [__("OAI server"), __("Server ID or name")],
  };

  function recordName(kind) {
    return PREVIEW_RECORDS[kind] ? PREVIEW_RECORDS[kind][0] : kind;
  }

  // The fields of the records the notice receives, all optional. Notices
  // combining items take several items
  function showPreviewRecords(kinds, combines) {
    var li = $("#notice_editor_preview_records");
    li.empty();
    if (!kinds || !kinds.length) {
      li.hide();
      return;
    }
    li.append($('<span class="label"></span>').text(__("Preview with:")));
    kinds.forEach(function (kind) {
      var several = combines && kind === "item";
      li.append(
        $('<label class="inline"></label>')
          .attr("for", "preview_record_" + kind)
          .text(" " + (several ? __("Items") : recordName(kind)) + ": "),
        $('<input type="text" class="preview_record" />').attr({
          id: "preview_record_" + kind,
          "data-kind": kind,
          placeholder: several
            ? __("Barcodes, separated by commas")
            : PREVIEW_RECORDS[kind]
              ? PREVIEW_RECORDS[kind][1]
              : "",
        }),
      );
    });
    li.append(
      $('<div class="hint"></div>').text(
        __(
          "Optional. The preview uses these records and the ones related to them (e.g. a patron's checkouts, a basket's orders), or examples when there are none.",
        ),
      ),
    );
    if (combines) {
      li.append(
        $('<div class="hint"></div>').text(
          __(
            "This notice is sent once per item, and the notices for several items are combined into one message while the first is not sent yet: preview them with several items, or with the patron's (up to 3). Lines of ---- separate the header and the footer of the notice from what is repeated for each item.",
          ),
        ),
      );
    }
    li.show();
  }

  var PREVIEW_NOTES = {
    sample_patron: function () {
      return [
        document.createTextNode(
          __("No patron was given: an example patron is used."),
        ),
      ];
    },
    sample: function (v) {
      return messageNodes(
        __("%s: none is related to these records, an example record is used."),
        [v],
      );
    },
    partial: function (v) {
      return messageNodes(
        __(
          "%s: none is related to all these records, one related to some of them is used.",
        ),
        [v],
      );
    },
    no_overdues: function (v) {
      return messageNodes(
        __("%s: the patron has no overdues, their checkouts are used."),
        [v],
      );
    },
    missing: function (v) {
      return messageNodes(
        __("%s: no record of this kind was found, it is empty."),
        [v],
      );
    },
    placeholder: function (v) {
      return messageNodes(__("%s: shown as [%s]."), [
        v,
        $("<span></span>").text(v),
      ]);
    },
    no_data: function (v) {
      return messageNodes(__("%s: empty in the preview."), [v]);
    },
  };

  // The notice as it is shown to patrons, in a sandboxed frame as Koha shows
  // the notices of patrons (bug 33260): nothing in it can run, and the CSS of
  // the notice and of the page do not apply to each other
  function noticePreview(html) {
    return $('<iframe class="notice-preview-frame" sandbox=""></iframe>')
      .attr("title", __("Notice content"))
      .attr("srcdoc", html)
      .css({ border: 0, height: "60vh", width: "100%" })[0];
  }

  function showPreview(response, source) {
    var body = $("<div></div>");
    response.messages.forEach(function (message) {
      body.append(
        message.code === "combined"
          ? $('<div class="alert alert-info"></div>').text(
              __(
                "The notices for %s items are combined into one message, as they are when sent.",
              ).format(message.value),
            )
          : $('<div class="alert alert-warning"></div>').text(
              __("%s '%s' was not found.").format(
                message.kind === "item" ? __("Item") : recordName(message.kind),
                message.value,
              ),
            ),
      );
    });
    if (response.patron) {
      body.append(
        $("<p></p>").text(
          __("Previewed for %s (%s).").format(
            response.patron.name,
            response.patron.cardnumber || "",
          ),
        ),
      );
    }
    if (response.notes.length) {
      var list = $("<ul></ul>");
      response.notes.forEach(function (note) {
        var describe = PREVIEW_NOTES[note.code];
        list.append(
          $("<li></li>").append(describe ? describe(note.variable) : note.code),
        );
      });
      body.append(
        $('<div class="alert alert-info preview-notes"></div>').append(
          $("<span></span>").text(
            __(
              "Some data of this preview does not come from the records it is previewed with:",
            ),
          ),
          list,
        ),
      );
    }
    var row = $('<div class="row"></div>');
    row.append(
      $('<div class="col-6"></div>').append(
        $("<h3></h3>").text(__("Template")),
        $('<pre class="notice-preview-source"></pre>').text(source),
      ),
      $('<div class="col-6"></div>').append(
        $("<h3></h3>").text(__("Rendered notice")),
        $('<p class="notice-preview-subject"></p>')
          .append($('<span class="label"></span>').text(__("Subject:")))
          .append(document.createTextNode(" " + response.title)),
        $('<div class="notice-preview"></div>').append(
          noticePreview(response.html),
        ),
      ),
    );
    $("#preview_template .modal-body").empty().append(body, row);
  }

  // The records entered to preview the notice with, by kind
  function previewRecords() {
    var records = {};
    $(".preview_record").each(function () {
      var value = $(this).val().trim();
      if (value) {
        records[$(this).data("kind")] = value;
      }
    });
    return records;
  }

  $(document).ready(function () {
    var form = $("#add_notice");
    var code = $("#code");
    if (!form.length || !$("fieldset.mtt").length || !code.val()) {
      return;
    }

    // The records to preview with, instead of the "Data for preview" of core:
    // filled with those the notice receives when its fields are loaded
    $("#data_preview").closest("li").remove();
    if (!$("#notice_editor_preview_records").length) {
      $("#name")
        .closest("li")
        .after($('<li id="notice_editor_preview_records"></li>').hide());
    }

    // A preview for every template, instead of the previews of core
    $(".preview_template").closest("li").remove();
    $("fieldset.mtt").each(function () {
      var fieldset = $(this);
      ensureLineGutter(fieldset);
      var preview = $(
        '<a href="#" class="btn btn-default btn-xs notice_editor_preview"><i class="fa-solid fa-eye"></i> </a>',
      )
        .attr(
          "data-mtt",
          fieldset.find('input[name="message_transport_type"]').val(),
        )
        .attr("data-lang", fieldset.find('input[name="lang"]').val())
        .append(document.createTextNode(__("Preview")));
      fieldset.children("ol").append($("<li></li>").append(preview));
    });

    // Enter in the records to preview with previews the template shown,
    // instead of submitting the notice
    $("body").on("keydown", ".preview_record", function (e) {
      if (e.key !== "Enter") {
        return;
      }
      e.preventDefault();
      $("fieldset.mtt:visible .notice_editor_preview").first().trigger("click");
    });

    var preview_request;
    $("body").on("click", ".notice_editor_preview", function (e) {
      e.preventDefault();
      var mtt = $(this).data("mtt");
      var lang = $(this).data("lang");
      var content = $("#content_" + mtt + "_" + lang).val();
      $("#preview_template .modal-body").html(modal_loading);
      $("#preview_template").modal("show");
      // Only the latest preview is shown: a slower earlier one must not
      // replace it
      if (preview_request) {
        preview_request.abort();
      }
      var request = $.ajax({
        url: API + "/preview",
        type: "POST",
        contentType: "application/json",
        dataType: "json",
        data: JSON.stringify({
          module: form.find("select[name='module']").val(),
          code: code.val(),
          message_transport_type: mtt,
          lang: lang,
          title: $("#title_" + mtt + "_" + lang).val(),
          content: content,
          is_html: $("#is_html_" + mtt + "_" + lang).is(":checked"),
          style: $("#style_" + lang).val() || "",
          records: previewRecords(),
        }),
      });
      preview_request = request;
      request.then(
        function (response) {
          if (request !== preview_request) return;
          showPreview(response, content);
        },
        function (xhr, status) {
          if (request !== preview_request || status === "abort") return;
          $("#preview_template .modal-body")
            .empty()
            .append(
              $('<div class="alert alert-danger"></div>').text(
                __("The notice could not be previewed."),
              ),
            );
        },
      );
    });
  });
})();
