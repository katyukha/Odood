# Migrate addons code to next Odoo serie

Odood provides ability to migrate addon code to next odoo serie.
This is implemented via `odood repo migrate-addons` command, that
under the hood uses [odoo-module-migrator](https://github.com/OCA/odoo-module-migrator) project.

For example, yo have to take following steps to migrate repo from Odoo 17 to Odoo 18:
- Add repo to Odood project for Odoo 18
- Create new branch in repo *18.0* based on stable *17.0*
- Run `odood repo migrate-addons` inside repo with addons to be migrated.
- Test that everything works fine, and fix (or disable) things that are broken.
- Commit changes and push changes.

## Example

For example, let's assume that we want to migrate repo `https://github.com/myname/myrepo` from `17.0` to `18.0`.

As pre requisite for this task we have to have Odoo 18 development installation installed via Odood.
(if you do not have it, you can install it via command `odood init -v 18 -i odoo-18 --db-user=odoo18 --http-port=18069 --create-db-user`)

So, let's fetch this repo in Odoo 18 project:

```bash
cd odoo-18
odood repo add -b 17.0 git@github.com:myname/myrepo
```

After this step, we will have repo clonned in `repositories/myname/myrepo`.
So, let's change directory to that one:

```bash
cd repositories/myname/myrepo
```

Next, we have to create new `18.0` branch:

```bash
git checkout -b 18.0
```

(branch name represnents that version of Odoo, for which addons on this branch expected to work fine)

So, next, we have to run migrator to actually migrate code of addons:

```bash
odood repo migrate-addons
```

Check output of this command, myabe there are some notes or some hits to something that was not migrated automatically.
Try to fix it. Test if everything works fine. Fix broken things and commit.

That's all.

## Notes

Possibly, it could be better strategy to migrate addons one by one.
In this case, you can specify name of addon that you want to migrate:

```bash
odood repo migrate-addons -m my_module
```

(In this case, `my_module` is name of module to migrate. This option could be specified multiple times).
