# Translation Management

## Overview

Odood automates the full translation workflow for Odoo addons: generating `.pot` template files,
creating or updating `.po` translation files, and deduplicating entries.
All translation work is done through a temporary database that Odood creates, uses, and drops automatically.

> **Prerequisite:** The `gettext` package must be installed on your system (`msgmerge`, `msguniq`).
> On Debian/Ubuntu: `sudo apt install gettext`.

---

## How Odoo translations work

Each addon stores translations under `i18n/`:

```
my_addon/
└── i18n/
    ├── my_addon.pot   ← template: all translatable strings extracted from source
    ├── uk.po          ← Ukrainian translations
    ├── de.po          ← German translations
    └── fr.po          ← French translations
```

The `.pot` file is the source of truth for *what* needs translating — it is extracted directly
from the addon's Python, XML, and CSV files by Odoo itself.
The `.po` files contain the actual translations (`msgstr` values) for a specific language.

---

## The correct workflow

### Initial setup (new addon or new language)

Generate the `.pot` file and create `.po` files for the first time:

```bash
odood translations regenerate \
    --pot \
    --pot-remove-dates \
    -l uk_UA \
    --addon-dir .
```

This creates `i18n/<addon>.pot` and `i18n/uk.po` for every installable addon found under `.`.
The `.po` files will have all `msgstr` values empty — ready to be filled in.

### After adding new translatable strings

When source code adds new strings, update existing `.po` files without overwriting already-translated entries:

```bash
odood translations regenerate \
    --pot \
    --pot-remove-dates \
    --pot-update \
    --missing-only \
    -l uk_UA \
    --addon-dir .
```

- `--pot` regenerates the `.pot` from the current source.
- `--pot-update` merges the updated `.pot` into each `.po` file.
- `--missing-only` preserves existing `msgstr` values — only new strings get empty entries appended.

Odood automatically runs `msguniq` before the merge to eliminate duplicate `msgid` entries that
may have accumulated in the `.po` file.

### Targeting specific addons

Instead of `--addon-dir`, list addon names explicitly:

```bash
odood translations regenerate \
    --pot --pot-remove-dates --pot-update --missing-only \
    -l uk_UA \
    my_addon other_addon
```

### Multiple languages at once

Repeat `-l` for each language:

```bash
odood translations regenerate \
    --pot --pot-remove-dates --pot-update --missing-only \
    -l uk_UA \
    -l de_DE \
    -l fr_FR \
    --addon-dir .
```

### Custom language code / file name mapping

Some languages use a different file name than the language code prefix (e.g. `zh_TW` saved as `zh_Traditional`).
Use `--lang-file` for explicit control:

```bash
odood translations regenerate \
    --pot --pot-update --missing-only \
    --lang-file zh_TW:zh_Traditional \
    --addon-dir .
```

---

## Flag reference

| Flag | Description |
|---|---|
| `--pot` | Regenerate the `.pot` template file from the installed addon. |
| `--pot-update` | Merge the `.pot` into existing `.po` files with `msgmerge`. |
| `--missing-only` | Skip `.po` files that already exist unless `--pot-update` is also set; preserves existing `msgstr` values on merge. |
| `--pot-remove-dates` | Strip `POT-Creation-Date` and `PO-Revision-Date` headers. Recommended: reduces noise in git diffs. |
| `-l <lang>` | Language code in `ll_CC` format (e.g. `uk_UA`). The file is named after the language prefix (`uk.po`). Repeatable. |
| `--lang-file <lang:file>` | Explicit `language:filename` mapping (e.g. `zh_TW:zh_Traditional`). Repeatable. |
| `--addon-dir <path>` | Scan `<path>` (non-recursively) for installable linked addons. Repeatable. |
| `--addon-dir-r <path>` | Same as `--addon-dir` but recursive. Repeatable. |
| `--no-drop-db` | Keep the temporary database after the run (useful for debugging). |

---

## What to commit

Commit both `.pot` and `.po` files alongside your code changes.
The `.pot` file acts as a record of what the addon exposes for translation;
keeping it in version control makes it easy to see which strings changed in a given commit.

---

## Using AI assistants for translations

> **Important for AI-assisted workflows**

When using an AI assistant to help fill translations, always follow this order:

1. **Run `odood translations regenerate` first** to produce the correct `.po` structure with
   authoritative `msgid` entries extracted from the actual source code.
2. **Then ask the AI to fill only the `msgstr` values** in the generated file.

**Never ask an AI to write `msgid` lines from scratch.**
AI assistants frequently produce `msgid` strings that don't match the actual source strings,
introduce duplicate entries, or get plural forms wrong — all of which silently corrupt the
translation file and cause Odoo to ignore the affected translations.

Odood partially mitigates this by running `msguniq` automatically when `--missing-only --pot-update`
are both set, which deduplicates any repeated `msgid` entries before merging.
But the safest approach is to never let them appear in the first place.

**Correct workflow with an AI assistant:**

```bash
# 1. Generate the structure
odood translations regenerate \
    --pot --pot-remove-dates --pot-update --missing-only \
    -l uk_UA \
    --addon-dir .

# 2. Open the generated .po file and ask the AI to fill the empty msgstr values.
#    The AI reads existing msgid entries from the file — it does not invent them.
```
