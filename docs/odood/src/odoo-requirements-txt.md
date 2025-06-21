# odoo\_requirements.txt

*odoo_requirements.txt* file is a text file that describes what repositories have to be installed on Odoo instance.
Originally, this format comes from [odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/). Odood supports it too.

This file is parsed line by line, and each line must be set of options for [odoo-helper fetch](./command-reference.md#odoo-helper-fetch) command.

## Format

### Fetch addons form any git repository

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

### Fetch addons direcly from [Odoo Apps](https://apps.odoo.com/apps)

```
--odoo-app <app name>
```

## Notes

***Note*** *odoo_requirements.txt* must end with newline symbol.

## Examples

```
--github crnd-inc/generic-addon --module generic_tags -b 12.0
--oca project -m project_description
--odoo-app bureaucrat_helpdesk_lite
```
