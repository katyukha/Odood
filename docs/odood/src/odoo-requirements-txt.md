# odoo\_requirements.txt

*odoo_requirements.txt* is a text file that lists the repositories and apps to install on an Odoo instance.
The format originates from [odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/) and is supported by Odood.

## Usage

Install all repositories and apps listed in the file:

```bash
odood addons add --odoo-requirements path/to/odoo_requirements.txt
```

You can also pass a **directory** — Odood will look for `odoo_requirements.txt` inside it:

```bash
odood addons add --odoo-requirements path/to/my-project/
```

This is convenient when the file lives alongside your project's other config files and you want to point at the project root rather than the file itself.

## Format

The file is parsed line by line. Each non-empty, non-comment line is a set of options:

### Fetch addons from any git repository

```
-r|--repo <git repository>  [-b|--branch <git branch>]
```

### Fetch addons from github repository

```
--github <github username/reponame> [-b|--branch <git branch>]
```

### Fetch [OCA](https://odoo-community.org/) addons from any [OCA github repository](https://github.com/OCA)

```
--oca <OCA reponame> [-b|--branch <git branch>]
```

### Fetch addons directly from [Odoo Apps](https://apps.odoo.com/apps)

```
--odoo-app <app name>
```

## Notes

- The file must end with a newline character.
- Lines beginning with `#` are treated as comments and ignored.

## Example

```
# Third-party repos
--github crnd-inc/generic-addons --module generic_mixin -b 16.0
--oca project -m project_description

# From Odoo Apps
--odoo-app bureaucrat_helpdesk_lite
```
